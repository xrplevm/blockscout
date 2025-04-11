defmodule Indexer.Transform.AddressTokenBalances do
  @moduledoc """
  Extracts `Explorer.Address.TokenBalance` params from other schema's params.
  """

  import Explorer.Chain.SmartContract, only: [burn_address_hash_string: 0]

  def params_set(%{} = import_options) do
    Enum.reduce(import_options, MapSet.new(), &reducer/2)
  end

  defp reducer({:token_transfers_params, token_transfers_params}, initial) when is_list(token_transfers_params) do
    token_transfers_params
    |> Enum.reduce(initial, fn %{
                                 block_number: block_number,
                                 from_address_hash: from_address_hash,
                                 to_address_hash: to_address_hash,
                                 token_contract_address_hash: token_contract_address_hash,
                                 token_ids: token_ids,
                                 token: %{type: token_type}
                               },
                               acc
                               when is_integer(block_number) and is_binary(from_address_hash) and
                                      is_binary(to_address_hash) and is_binary(token_contract_address_hash) ->
      sanitized_token_ids =
        if is_nil(token_ids) || (is_list(token_ids) && Enum.empty?(token_ids)), do: [nil], else: token_ids

      Enum.reduce(sanitized_token_ids, acc, fn id, sub_acc ->
        sub_acc
        |> add_token_balance_address(from_address_hash, token_contract_address_hash, id, token_type, block_number)
        |> add_token_balance_address(to_address_hash, token_contract_address_hash, id, token_type, block_number)
      end)
    end)
  end

    defp reducer({:transactions_params, transactions_params}, initial) when is_list(transactions_params) do
    # Here, we assume that a transaction with a non-zero "value" is a native transfer.
    transactions_params
    |> Enum.filter(fn %{value: value} ->
         # You may need to adjust this check according to how "value" is represented (e.g. Decimal.zero?/1)
         value && not Decimal.equal?(value, Decimal.new(0))
       end)
    |> Enum.reduce(initial, fn %{
                                 block_number: block_number,
                                 from_address_hash: from_address,
                                 to_address_hash: to_address,
                                 value: amount
                               },
                               acc ->
      # For your native token, assume its token_contract_address is your known native ERC-20 token.
      token_contract_address = System.get_env("NATIVE_TOKEN_ADDRESS")
      token_type = "ERC-20"

      # Update balances for both sender and receiver.
      acc
      |> add_token_balance_address(from_address, token_contract_address, nil, token_type, block_number)
      |> add_token_balance_address(to_address, token_contract_address, nil, token_type, block_number)
      # You might want to store the amount as well in your database or merge it with existing amounts.
    end)
  end

  defp add_token_balance_address(map_set, unquote(burn_address_hash_string()), _, _, _, _), do: map_set

  defp add_token_balance_address(map_set, address, token_contract_address, token_id, token_type, block_number) do
    MapSet.put(map_set, %{
      address_hash: address,
      token_contract_address_hash: token_contract_address,
      block_number: block_number,
      token_id: token_id,
      token_type: token_type
    })
  end
end
