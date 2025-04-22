defmodule Indexer.XRPLEVM.IntegrationTest do
  use EthereumJSONRPC.Case, async: false
  use Explorer.DataCase

  import EthereumJSONRPC, only: [integer_to_quantity: 1, quantity_to_integer: 1]
  import Mox

  alias Explorer.Chain.{Address, Hash, Wei}
  alias Explorer.Chain.Cache.BlockNumber
  alias Indexer.Fetcher.CoinBalance.Catchup, as: CoinBalanceCatchup

  alias Explorer.Repo

  @moduletag :capture_log

  setup :verify_on_exit!
  setup :set_mox_global

  setup do
    start_supervised!({Task.Supervisor, name: Indexer.TaskSupervisor})

    initial_config = Application.get_env(:explorer, Explorer.Chain.Cache.BlockNumber)
    Application.put_env(:explorer, Explorer.Chain.Cache.BlockNumber, enabled: true)

    on_exit(fn ->
      Application.put_env(:explorer, Explorer.Chain.Cache.BlockNumber, initial_config)
    end)

    :ok
  end

  defp eth_block_number_fake_response(block_quantity) do
    %{
      id: 0,
      jsonrpc: "2.0",
      result: %{
        "author" => "0x0000000000000000000000000000000000000000",
        "difficulty" => "0x20000",
        "extraData" => "0x",
        "gasLimit" => "0x663be0",
        "gasUsed" => "0x0",
        "hash" => "0x5b28c1bfd3a15230c9a46b399cd0f9a6920d432e85381cc6a140b06e8410112f",
        "logsBloom" => "...",
        "miner" => "0x0000000000000000000000000000000000000000",
        "number" => block_quantity,
        "parentHash" => "0x0000000000000000000000000000000000000000000000000000000000000000",
        "receiptsRoot" => "...",
        "sealFields" => ["0x80", "..."],
        "sha3Uncles" => "...",
        "signature" => "...",
        "size" => "0x215",
        "stateRoot" => "...",
        "step" => "0",
        "timestamp" => "0x0",
        "totalDifficulty" => "0x20000",
        "transactions" => [],
        "transactionsRoot" => "...",
        "uncles" => []
      }
    }
  end

  test "updating native token balance updates coin balance" do
    address = insert(:address)
    block = insert(:block, number: 12345)
    native_token_address = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE"
    System.put_env("NATIVE_TOKEN_ADDRESS", native_token_address)

    # Insert a token balance for the native token
    token_balance_params = [
      %{
        address_hash: to_string(address.hash),
        block_number: block.number,
        token_contract_address_hash: native_token_address,
        token_id: nil,
        value: 42_000_000,
        token_type: "ERC-20"
      }
    ]

    # Call the import function (or the function that triggers the sync)
    assert :ok = Indexer.Fetcher.TokenBalance.import_token_balances(token_balance_params)

    # Assert token balance exists
    token_balance =
      Explorer.Chain.Address.TokenBalance
      |> where([tb], tb.address_hash == ^address.hash and tb.token_contract_address_hash == ^native_token_address)
      |> Repo.one()

    assert token_balance.value == Decimal.new(42_000_000)

    # Assert coin balance was also updated
    coin_balance =
      Explorer.Chain.Address.CoinBalance
      |> where([cb], cb.address_hash == ^address.hash)
      |> Repo.one()

    assert coin_balance.value == %Wei{value: Decimal.new(42_000_000)}  end

  test "importing native coin balance also creates native token balance" do
       # Set up the native token address as in your env
      native_token_address = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE"
      System.put_env("NATIVE_TOKEN_ADDRESS", native_token_address)

      # Insert an address and block
      address = insert(:address)
      block_number = block_number()
      block_quantity = integer_to_quantity(block_number)
      res = eth_block_number_fake_response(block_quantity)
      # Prepare coin balance params as would be fetched
      coin_balance_params = [
        %{
          address_hash: to_string(address.hash),
          block_number: block_number,
          value: Decimal.new(123_456_789),
          value_fetched_at: DateTime.utc_now()
        }
      ]


      EthereumJSONRPC.Mox
      |> expect(:json_rpc, fn [
            %{
              id: 0,
              jsonrpc: "2.0",
              method: "eth_getBlockByNumber",
              params: [^block_quantity, true]
            }
          ], _options ->
        {:ok, [res]} # Use your eth_block_number_fake_response/1 helper
      end)

      # Call the import_fetched_balances function
      result = Indexer.Fetcher.CoinBalance.Helper.import_fetched_balances(coin_balance_params)
      assert match?({:ok, _}, result)

      # Assert coin balance exists
      coin_balance =
        Explorer.Chain.Address.CoinBalance
        |> where([cb], cb.address_hash == ^address.hash and cb.block_number == ^block_number)
        |> Repo.one()

      assert coin_balance.value == %Explorer.Chain.Wei{value: Decimal.new(123_456_789)}

      # Assert token balance for the native token was also created
      token_balance =
        Explorer.Chain.Address.TokenBalance
        |> where([tb], tb.address_hash == ^address.hash and tb.block_number == ^block_number and tb.token_contract_address_hash == ^native_token_address)
        |> Repo.one()

      assert token_balance.value == Decimal.new(123_456_789)
      assert token_balance.token_type == "ERC-20"
    end
end
