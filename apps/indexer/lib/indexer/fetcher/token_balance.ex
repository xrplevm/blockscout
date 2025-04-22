defmodule Indexer.Fetcher.TokenBalance do
  @moduledoc """
  Fetches token balances and sends the ones that were fetched to be imported in `Address.CurrentTokenBalance` and
  `Address.TokenBalance`.

  The module responsible for fetching token balances in the Smart Contract is the `Indexer.TokenBalances`. This module
  only prepares the params, sends them to `Indexer.TokenBalances` and relies on its return.

  It behaves as a `BufferedTask`, so we can configure the `max_batch_size` and the `max_concurrency` to control how many
  token balances will be fetched at the same time.

  Also, this module set a `refetch_after` for each token balance in case of failure to avoid fetching the ones
  that always raise errors interacting with the Smart Contract.
  """

  use Indexer.Fetcher, restart: :permanent
  use Spandex.Decorators

  require Logger

  alias Explorer.Chain
  alias Explorer.Chain.Address.{CurrentTokenBalance, TokenBalance}
  alias Explorer.Chain.Hash
  alias Explorer.Utility.MissingBalanceOfToken
  alias Indexer.{BufferedTask, TokenBalances, Tracer}
  alias Indexer.Fetcher.TokenBalance.Supervisor, as: TokenBalanceSupervisor

  import Indexer.Fetcher.CoinBalance.Helper, only: [balances_daily_params: 2]

  @behaviour BufferedTask

  @default_max_batch_size 100
  @default_max_concurrency 10

  @timeout :timer.minutes(10)

  @spec async_fetch(
          [
            %{
              token_contract_address_hash: Hash.Address.t(),
              address_hash: Hash.Address.t(),
              block_number: non_neg_integer(),
              token_type: String.t(),
              token_id: non_neg_integer()
            }
          ],
          boolean()
        ) :: :ok
  def async_fetch(token_balances, realtime?) do
    if TokenBalanceSupervisor.disabled?() do
      :ok
    else
      formatted_params = Enum.map(token_balances, &entry/1)

      BufferedTask.buffer(__MODULE__, formatted_params, realtime?, :infinity)
    end
  end

  @doc false
  def child_spec([init_options, gen_server_options]) do
    {state, mergeable_init_options} = Keyword.pop(init_options, :json_rpc_named_arguments)

    unless state do
      raise ArgumentError,
            ":json_rpc_named_arguments must be provided to `#{__MODULE__}.child_spec " <>
              "to allow for json_rpc calls when running."
    end

    merged_init_opts =
      defaults()
      |> Keyword.merge(mergeable_init_options)
      |> Keyword.put(:state, state)

    Supervisor.child_spec({BufferedTask, [{__MODULE__, merged_init_opts}, gen_server_options]}, id: __MODULE__)
  end

  @impl BufferedTask
  def init(initial, reducer, _) do
    {:ok, final} =
      Chain.stream_unfetched_token_balances(
        initial,
        fn token_balance, acc ->
          token_balance
          |> entry()
          |> reducer.(acc)
        end,
        true
      )

    final
  end

  @doc """
  Fetches the given entries (token_balances) from the Smart Contract and import them in our database.

  It also set the `refetch_after` in case of failure to avoid fetching token balances that always raise errors
  when reading their balance in the Smart Contract.
  """
  @impl BufferedTask
  @decorate trace(name: "fetch", resource: "Indexer.Fetcher.TokenBalance.run/2", tracer: Tracer, service: :indexer)
  def run(entries, _json_rpc_named_arguments) do
    params = Enum.map(entries, &format_params/1)

    missing_balance_of_tokens =
      params
      |> Enum.map(& &1.token_contract_address_hash)
      |> Enum.uniq()
      |> MissingBalanceOfToken.get_by_hashes()

    result =
      params
      |> MissingBalanceOfToken.filter_token_balances_params(true, missing_balance_of_tokens)
      |> fetch_from_blockchain(missing_balance_of_tokens)
      |> import_token_balances()

    if result == :ok do
      :ok
    else
      {:retry, entries}
    end
  end

  def fetch_from_blockchain(params_list, missing_balance_of_tokens) do
    params_list =
      Enum.uniq_by(params_list, &Map.take(&1, [:token_contract_address_hash, :token_id, :address_hash, :block_number]))

    Logger.metadata(count: Enum.count(params_list))

    {:ok, %{fetched_token_balances: fetched_token_balances, failed_token_balances: failed_token_balances}} =
      TokenBalances.fetch_token_balances_from_blockchain(params_list)

    handle_success_balances(fetched_token_balances, missing_balance_of_tokens)
    failed_balances_to_keep = handle_failed_balances(failed_token_balances)

    fetched_token_balances ++ failed_balances_to_keep
  end

  defp handle_success_balances([], _missing_balance_of_tokens), do: :ok

  defp handle_success_balances(fetched_token_balances, missing_balance_of_tokens) do
    successful_token_hashes =
      fetched_token_balances
      |> Enum.map(&to_string(&1.token_contract_address_hash))
      |> MapSet.new()

    missing_balance_of_token_hashes =
      missing_balance_of_tokens
      |> Enum.map(&to_string(&1.token_contract_address_hash))
      |> MapSet.new()

    successful_token_hashes
    |> MapSet.intersection(missing_balance_of_token_hashes)
    |> MapSet.to_list()
    |> MissingBalanceOfToken.mark_as_implemented()
  end

  defp handle_failed_balances([]), do: []

  defp handle_failed_balances(failed_token_balances) do
    failed_token_balances
    |> handle_missing_balance_of_tokens()
    |> handle_other_errors()
  end

  defp handle_missing_balance_of_tokens(failed_token_balances) do
    {missing_balance_of_balances, other_failed_balances} =
      Enum.split_with(failed_token_balances, fn
        %{error: :unable_to_decode} -> true
        %{error: error} when is_binary(error) -> error =~ "execution reverted"
        _ -> false
      end)

    MissingBalanceOfToken.insert_from_params(missing_balance_of_balances)

    missing_balance_of_balances
    |> Enum.group_by(& &1.token_contract_address_hash, & &1.block_number)
    |> Enum.map(fn {token_contract_address_hash, block_numbers} ->
      {token_contract_address_hash, Enum.max(block_numbers)}
    end)
    |> Enum.each(fn {token_contract_address_hash, block_number} ->
      TokenBalance.delete_placeholders_below(token_contract_address_hash, block_number)
      CurrentTokenBalance.delete_placeholders_below(token_contract_address_hash, block_number)
    end)

    other_failed_balances
  end

  defp handle_other_errors(failed_token_balances) do
    Enum.map(failed_token_balances, fn token_balance_params ->
      new_retries_count = token_balance_params.retries_count + 1

      Map.merge(token_balance_params, %{
        retries_count: new_retries_count,
        refetch_after: define_refetch_after(new_retries_count)
      })
    end)
  end

  defp define_refetch_after(retries_count) do
    config = Application.get_env(:indexer, __MODULE__)

    coef = config[:exp_timeout_coeff]
    max_refetch_interval = config[:max_refetch_interval]
    max_retries_count = :math.log(max_refetch_interval / 1000 / coef)

    value = floor(coef * :math.exp(min(retries_count, max_retries_count)))

    Timex.shift(Timex.now(), seconds: value)
  end

  def import_token_balances(token_balances_params) do
    # Existing formatting and filtering steps
    addresses_params = format_and_filter_address_params(token_balances_params)
    formatted_token_balances_params = format_and_filter_token_balance_params(token_balances_params)

    # Apply transformer on the formatted token balances to get potential coin balance entries.
    transformed_params =
      Indexer.Transformers.TokenToCoinBalanceTransformer.transform_address_token_balances(
        formatted_token_balances_params
      )

    # Separate into token balance entries and coin balance entries.
    {final_token_balances, coin_balance_entries} =
      Enum.split_with(transformed_params, fn
        {:address_coin_balance, _} -> false
        _ -> true
      end)

    # Process current token balances as before, using output from the transformer.
    final_current_token_balances = TokenBalances.to_address_current_token_balances(final_token_balances)

    coin_balance_params =
      Enum.map(coin_balance_entries, fn {:address_coin_balance, coin_balance} -> coin_balance end)

    json_rpc_named_arguments = Application.get_env(:explorer, :json_rpc_named_arguments)
    importable_balances_daily_params = balances_daily_params(coin_balance_params, json_rpc_named_arguments)

    # Build import params, now including coin balances.
    import_params = %{
      addresses: %{params: addresses_params, with: :balance_changeset},
      address_token_balances: %{params: final_token_balances},
      address_current_token_balances: %{params: final_current_token_balances},
      address_coin_balances: %{params: coin_balance_params},
      address_coin_balances_daily: %{params: importable_balances_daily_params},
      timeout: @timeout
    }

    case Chain.import(import_params) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.debug(fn -> ["failed to import token balances: ", inspect(reason)] end,
          error_count: Enum.count(token_balances_params)
        )

        :error
    end
  end

  defp format_and_filter_address_params(token_balances_params) do
    token_balances_params
    |> Enum.group_by(& &1.address_hash)
    |> Map.values()
    |> Stream.map(&Enum.max_by(&1, fn %{block_number: block_number} -> block_number end))
    |> Enum.map(fn %{address_hash: address_hash, block_number: block_number, value: value} ->
      %{hash: address_hash, fetched_coin_balance_block_number: block_number, fetched_coin_balance: value}
    end)
  end

  defp format_and_filter_token_balance_params(token_balances_params) do
    token_balances_params
    |> Enum.map(fn token_balance ->
      if token_balance.token_type do
        token_balance
      else
        put_token_type_to_balance_object(token_balance)
      end
    end)
  end

  defp put_token_type_to_balance_object(token_balance) do
    token_type = Chain.get_token_type(token_balance.token_contract_address_hash)

    if token_type do
      Map.put(token_balance, :token_type, token_type)
    else
      token_balance
    end
  end

  defp entry(
         %{
           token_contract_address_hash: token_contract_address_hash,
           address_hash: address_hash,
           block_number: block_number,
           token_type: token_type,
           token_id: token_id
         } = params
       ) do
    token_id_int =
      case token_id do
        %Decimal{} -> Decimal.to_integer(token_id)
        id_int when is_integer(id_int) -> id_int
        _ -> token_id
      end

    {
      address_hash.bytes,
      token_contract_address_hash.bytes,
      block_number,
      token_type,
      token_id_int,
      Map.get(params, :retries_count) || 0
    }
  end

  defp format_params(
         {address_hash_bytes, token_contract_address_hash_bytes, block_number, token_type, token_id, retries_count}
       ) do
    {:ok, token_contract_address_hash} = Hash.Address.cast(token_contract_address_hash_bytes)
    {:ok, address_hash} = Hash.Address.cast(address_hash_bytes)

    %{
      token_contract_address_hash: to_string(token_contract_address_hash),
      address_hash: to_string(address_hash),
      block_number: block_number,
      retries_count: retries_count,
      token_type: token_type,
      token_id: token_id
    }
  end

  defp defaults do
    [
      flush_interval: 300,
      max_batch_size: Application.get_env(:indexer, __MODULE__)[:batch_size] || @default_max_batch_size,
      max_concurrency: Application.get_env(:indexer, __MODULE__)[:concurrency] || @default_max_concurrency,
      task_supervisor: Indexer.Fetcher.TokenBalance.TaskSupervisor
    ]
  end
end
