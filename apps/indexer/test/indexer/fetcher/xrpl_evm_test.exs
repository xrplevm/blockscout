defmodule Indexer.XRPLEVM.IntegrationTest do
  use EthereumJSONRPC.Case, async: false
  use Explorer.DataCase

  import EthereumJSONRPC, only: [integer_to_quantity: 1]
  import Mox

  alias Explorer.Chain.{Address, Wei}

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

    native_token_address = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE"
    System.put_env("NATIVE_TOKEN_ADDRESS", native_token_address)
    address = insert(:address)
    other_address = insert(:address)
    block_number = block_number()
    block_quantity = integer_to_quantity(block_number)
    res = eth_block_number_fake_response(block_quantity)

    {:ok,
     native_token_address: native_token_address,
     address: address,
     other_address: other_address,
     block_number: block_number,
     block_quantity: block_quantity,
     res: res}
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

  describe "import_token_balances/1 (token→coin)" do
    test "updating native token balance updates coin balance", %{
      native_token_address: native_token_address,
      address: address,
      block_number: block_number,
      block_quantity: block_quantity,
      res: res
    } do
      EthereumJSONRPC.Mox
      |> expect(:json_rpc, fn [
                                %{
                                  id: 0,
                                  jsonrpc: "2.0",
                                  method: "eth_getBlockByNumber",
                                  params: [^block_quantity, true]
                                }
                              ],
                              _options ->
        {:ok, [res]}
      end)

      token_balance_params = [
        %{
          address_hash: to_string(address.hash),
          block_number: block_number,
          token_contract_address_hash: native_token_address,
          token_id: nil,
          value: 42_000_000,
          token_type: "ERC-20"
        }
      ]

      assert :ok = Indexer.Fetcher.TokenBalance.import_token_balances(token_balance_params)

      token_balance =
        Explorer.Chain.Address.TokenBalance
        |> where([tb], tb.address_hash == ^address.hash and tb.token_contract_address_hash == ^native_token_address)
        |> Repo.one()

      assert token_balance.value == Decimal.new(42_000_000)

      coin_balance =
        Explorer.Chain.Address.CoinBalance
        |> where([cb], cb.address_hash == ^address.hash)
        |> Repo.one()

      assert coin_balance.value == %Wei{value: Decimal.new(42_000_000)}

      addr = Repo.get!(Address, address.hash)
      assert addr.fetched_coin_balance == %Wei{value: Decimal.new(42_000_000)}
      assert addr.fetched_coin_balance_block_number == block_number

      daily =
        Explorer.Chain.Address.CoinBalanceDaily
        |> where([d], d.address_hash == ^address.hash and d.value == ^Decimal.new(42_000_000))
        |> Repo.one()

      assert daily.day == ~D[1970-01-01]


    end

    test "importing non-native token balance does not update coin balance", %{
      address: address,
      other_address: other_address,
      block_number: block_number
    } do
      token_balance_params = [
        %{
          address_hash: to_string(address.hash),
          block_number: block_number,
          token_contract_address_hash: other_address.hash,
          token_id: nil,
          value: 42_000_000,
          token_type: "ERC-20"
        }
      ]

      assert :ok = Indexer.Fetcher.TokenBalance.import_token_balances(token_balance_params)

      coin_balance =
        Explorer.Chain.Address.CoinBalance
        |> where([cb], cb.address_hash == ^address.hash and cb.block_number == ^block_number)
        |> Repo.one()

      assert is_nil(coin_balance)
    end
  end

  describe "import_fetched_balances/2 (coin→token)" do
    test "importing native coin balance also creates native token balance", %{
      native_token_address: native_token_address,
      address: address,
      other_address: other_address,
      block_number: block_number,
      block_quantity: block_quantity,
      res: res
    } do
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
                              ],
                              _options ->
        {:ok, [res]}
      end)

      result = Indexer.Fetcher.CoinBalance.Helper.import_fetched_balances(coin_balance_params)
      assert match?({:ok, _}, result)

      coin_balance =
        Explorer.Chain.Address.CoinBalance
        |> where([cb], cb.address_hash == ^address.hash and cb.block_number == ^block_number)
        |> Repo.one()

      assert coin_balance.value == %Explorer.Chain.Wei{value: Decimal.new(123_456_789)}

      other_coin_balance =
        Explorer.Chain.Address.CoinBalance
        |> where([cb], cb.address_hash == ^other_address.hash)
        |> Repo.one()

      assert is_nil(other_coin_balance)

      token_balance =
        Explorer.Chain.Address.TokenBalance
        |> where(
          [tb],
          tb.address_hash == ^address.hash and tb.block_number == ^block_number and
            tb.token_contract_address_hash == ^native_token_address
        )
        |> Repo.one()

      assert token_balance.value == Decimal.new(123_456_789)
      assert token_balance.token_type == "ERC-20"

      current =
        Explorer.Chain.Address.CurrentTokenBalance
        |> where(
          [ctb],
          ctb.address_hash == ^address.hash and
            ctb.token_contract_address_hash == ^native_token_address
        )
        |> Repo.one()

      assert current.value == Decimal.new(123_456_789)


  addr = Repo.get!(Address, address.hash)
  assert addr.fetched_coin_balance == %Wei{value: Decimal.new(123_456_789)}
  assert addr.fetched_coin_balance_block_number == block_number
    end

    test "latest block snapshot wins", %{
      native_token_address: native_token_address,
      address: address,
      block_number: block_number
    } do
      b1 = block_number
      b2 = block_number + 1
      q1 = integer_to_quantity(b1)
      q2 = integer_to_quantity(b2)
      res1 = eth_block_number_fake_response(q1)
      res2 = eth_block_number_fake_response(q2)

      EthereumJSONRPC.Mox
      |> stub(:json_rpc, fn
        [%{method: "eth_getBlockByNumber", params: [^q1, true]}], _opts -> {:ok, [res1]}
        [%{method: "eth_getBlockByNumber", params: [^q2, true]}], _opts -> {:ok, [res2]}
      end)

      params = [
        %{
          address_hash: to_string(address.hash),
          block_number: b1,
          value: Decimal.new(100),
          value_fetched_at: DateTime.utc_now()
        },
        %{
          address_hash: to_string(address.hash),
          block_number: b2,
          value: Decimal.new(200),
          value_fetched_at: DateTime.utc_now()
        }
      ]

      assert {:ok, _} = Indexer.Fetcher.CoinBalance.Helper.import_fetched_balances(params)

      current =
        Explorer.Chain.Address.CurrentTokenBalance
        |> where([ctb], ctb.address_hash == ^address.hash and ctb.token_contract_address_hash == ^native_token_address)
        |> Repo.one()

      assert current.value == Decimal.new(200)
    end

    test "idempotent coin import doesn't duplicate rows", %{
      address: address,
      block_number: block_number
    } do
      EthereumJSONRPC.Mox
      |> stub(:json_rpc, fn [
                              %{
                                id: 0,
                                jsonrpc: "2.0",
                                method: "eth_getBlockByNumber",
                                params: [block_quantity, true]
                              }
                            ],
                            _options ->
        {:ok, [eth_block_number_fake_response(block_quantity)]}
      end)

      params = [
        %{
          address_hash: to_string(address.hash),
          block_number: block_number,
          value: Decimal.new(50),
          value_fetched_at: DateTime.utc_now()
        }
      ]

      assert {:ok, _} = Indexer.Fetcher.CoinBalance.Helper.import_fetched_balances(params)
      assert {:ok, _} = Indexer.Fetcher.CoinBalance.Helper.import_fetched_balances(params)

      assert Repo.aggregate(Explorer.Chain.Address.CoinBalance, :count, :block_number) == 1
      assert Repo.aggregate(Explorer.Chain.Address.CoinBalance, :count, :address_hash) == 1
    end
  end
end
