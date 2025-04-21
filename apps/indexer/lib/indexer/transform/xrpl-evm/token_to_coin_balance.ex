defmodule Indexer.Transformers.TokenToCoinBalanceTransformer do

  @doc """
  Transforms changes to `address_token_balances` into changes for `address_coin_balances`
  if the token contract address hash matches the hardcoded value.
  """
  def transform_address_token_balances(params) do
    native_token_address = System.get_env("NATIVE_TOKEN_ADDRESS")

    Enum.flat_map(params, fn token_balance ->
      if token_balance[:token_contract_address_hash] == native_token_address do
        # Create a corresponding address_coin_balance entry
        coin_balance = %{
          address_hash: token_balance[:address_hash],
          value: token_balance[:value],
          block_number: token_balance[:block_number],
          value_fetched_at: token_balance[:value_fetched_at]
        }

        [token_balance, {:address_coin_balance, coin_balance}]
      else
        [token_balance]
      end
    end)
  end
end
