defmodule Indexer.Transformers.CoinToTokenBalanceTransformer do
  @doc """
  Transforms changes to `address_coin_balances` into changes for `address_token_balances`
  if the native token address is set.
  """
  def transform_address_coin_balances(params) do
    native_token_address = System.get_env("NATIVE_TOKEN_ADDRESS")

    Enum.flat_map(params, fn coin_balance ->
      if native_token_address do
        token_balance = %{
          token_contract_address_hash: native_token_address,
          address_hash: coin_balance[:address_hash],
          block_number: coin_balance[:block_number],
          value: coin_balance[:value],
          token_type: "erc20",
          token_id: 0,
          value_fetched_at: coin_balance[:value_fetched_at]
        }

        [coin_balance, {:address_token_balance, token_balance}]
      else
        [coin_balance]
      end
    end)
  end
end
