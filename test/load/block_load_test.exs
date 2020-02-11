defmodule Kniffel.LoadTest do
  use Kniffel.DataCase

  alias Kniffel.User

  import Kniffel.Factory
  import Mox

  def flush_cache(_context) do
    Kniffel.Cache.flush()
    :ok
  end

  setup :flush_cache
  setup :set_mox_global

  def create_this_server() do
    {:ok, private_key} = ExPublicKey.generate_key(4096)

    Kniffel.CryptoMock
    |> stub(:private_key, fn -> {:ok, private_key} end)

    server_key = Kniffel.CryptoHelper.generate_fields_from_rsa_key(private_key)

    {:ok, this_server} =
      %Kniffel.Server{}
      |> cast(
        %{
          url: "https://test.de",
          public_key: server_key.public_pem_string,
          authority: true,
          id: server_key.id
        },
        [:id, :url, :public_key, :authority]
      )
      |> Repo.insert()

    {server_key, this_server}
  end

  def create_server(authority \\ false) do
    server_key = Kniffel.CryptoHelper.create_rsa_key()
    {:ok, server} = insert_server(server_key, authority)
    {server_key, server}
  end

  def insert_server(server_key, authority) do
    %Kniffel.Server{}
    |> cast(
      %{
        url: "https://test.kniffel.app",
        public_key: server_key.public_pem_string,
        authority: authority,
        id: server_key.id
      },
      [:id, :url, :public_key, :authority]
    )
    |> Repo.insert()
  end

  def insert_user do
    user_key = Kniffel.CryptoHelper.create_rsa_key()

    user_params = %{
      "password" => "Abc123de!",
      "password_confirmation" => "Abc123de!",
      "private_key" => user_key.private_pem_string,
      "user_name" => "test_user"
    }

    {:ok, user} =
      %User{}
      |> User.change_user(user_params)
      |> Repo.insert()

    {user_key, user}
  end

  @tag :load
  @tag timeout: :infinity
  test "benchmark_propose_to_server" do
    transaction_block_limit = Application.get_env(:kniffel, :block_transaction_limit)

    Kniffel.Scheduler.RoundSpecification.set_round_specification(
      Kniffel.Scheduler.RoundSpecification.get_default_round_specification()
    )

    {server_key, server} = create_server(true)
    {_user_key, _user} = insert_user()

    {_this_server_key, this_server} = create_this_server()

    Kniffel.Blockchain.genesis()

    transactions = insert_list(transaction_block_limit, :not_correct_signed_transaction)

    propose =
      Map.new()
      |> Map.put(:transactions, transactions)
      |> Map.put(:block, Kniffel.Blockchain.get_last_block())
      |> Map.put(:server, this_server)
      |> Kniffel.Blockchain.Block.Propose.change()

    signature =
      %{hash: Kniffel.Blockchain.Block.Propose.hash(propose), error: :none}
      |> Poison.encode!()
      |> Kniffel.Blockchain.Crypto.sign(server_key.private_pem_string)

    propose_response = %Kniffel.Blockchain.Block.ProposeResponse{
      server_id: server.id,
      hash: Kniffel.Blockchain.Block.Propose.hash(propose),
      signature: signature
    }

    Kniffel.Cache.delete({:propose, block_index: propose.block_index})
    Kniffel.Cache.delete({:propose_response, block_index: propose.block_index})

    Kniffel.Cache.set({:propose, block_index: propose.block_index}, propose)

    stub(Kniffel.RequestMock, :post, fn _server_url,
                                        %{
                                          propose: _propose,
                                          round_specification: _round_specification
                                        } ->
      {:ok,
       %{
         "propose_response" => %{
           "hash" => propose_response.hash,
           "server_id" => propose_response.server_id,
           "error" => Atom.to_string(propose_response.error),
           "signature" => propose_response.signature
         }
       }}
    end)

    Benchee.run(
      %{
        "propose_to_server" => fn {server, propose} ->
          Kniffel.Blockchain.propose_to_server(server, propose)
        end
      },
      after_each: fn result ->
        assert %Kniffel.Blockchain.Block.ProposeResponse{} = result
        assert :none = result.error
      end,
      inputs: %{"test" => {server, propose}},
      time: 10,
      memory_time: 2
    )
  end

  @tag :load
  @tag timeout: :infinity
  test "benchmark_validate_block_proposal" do
    transaction_block_limit = Application.get_env(:kniffel, :block_transaction_limit)

    Kniffel.Scheduler.RoundSpecification.set_round_specification(
      Kniffel.Scheduler.RoundSpecification.get_default_round_specification()
    )

    {_server_key, server} = create_server(true)
    {user_key, user} = insert_user()

    {_this_server_key, this_server} = create_this_server()

    Kniffel.Blockchain.genesis()

    timestamp = Timex.now() |> Timex.format!("{ISO:Extended}")
    data = Poison.encode!(%{"games" => [], "scores" => []})

    signature =
      %{data: data, timestamp: timestamp}
      |> Poison.encode!()
      |> Kniffel.Blockchain.Crypto.sign(user_key.private_pem_string)

    transactions =
      build_list(transaction_block_limit, :not_correct_signed_transaction, %{
        user_id: user.id,
        signature: signature,
        data: data,
        timestamp: timestamp
      })

    propose =
      Map.new()
      |> Map.put(:transactions, transactions)
      |> Map.put(:block, Kniffel.Blockchain.get_last_block())
      |> Map.put(:server, this_server)
      |> Kniffel.Blockchain.Block.Propose.change()

    stub(Kniffel.RequestMock, :get, fn "https://test.de/api/transactions/" <> id ->
      transaction = Enum.find(transactions, &(&1.id == id))

      transaction_data = %{
        "id" => transaction.id,
        "data" => transaction.data,
        "signature" => transaction.signature,
        "timestamp" => transaction.timestamp,
        "user_id" => transaction.user_id,
        "block_index" => transaction.block_index
      }

      {:ok, %{"transaction" => transaction_data}}
    end)

    assert 0 = Enum.count(Kniffel.Blockchain.get_transactions(%{}))

    Benchee.run(
      %{
        "validate_block_proposal" => fn {_server, propose} ->
          Kniffel.Blockchain.validate_block_proposal(propose)
        end
      },
      after_each: fn result ->
        assert %Kniffel.Blockchain.Block.ProposeResponse{} = result
        assert :none = result.error
        assert transaction_block_limit = Enum.count(Kniffel.Blockchain.get_transactions(%{}))
      end,
      inputs: %{"test" => {server, propose}},
      time: 10,
      memory_time: 2
    )
  end

  @tag :load
  @tag timeout: :infinity
  test "benchmark_propose_new_block" do
    transaction_block_limit = Application.get_env(:kniffel, :block_transaction_limit)

    Kniffel.Scheduler.RoundSpecification.set_round_specification(
      Kniffel.Scheduler.RoundSpecification.get_default_round_specification()
    )

    {_server_key, _server} = create_server(true)
    {user_key, user} = insert_user()

    {_this_server_key, _this_server} = create_this_server()

    Kniffel.Blockchain.genesis()

    timestamp = Timex.now() |> Timex.format!("{ISO:Extended}")
    data = Poison.encode!(%{"games" => [], "scores" => []})

    signature =
      %{data: data, timestamp: timestamp}
      |> Poison.encode!()
      |> Kniffel.Blockchain.Crypto.sign(user_key.private_pem_string)

    transactions =
      insert_list(transaction_block_limit, :not_correct_signed_transaction, %{
        user_id: user.id,
        signature: signature,
        data: data,
        timestamp: timestamp
      })

    stub(Kniffel.BlockchainMock, :propose_to_server, fn _server, propose ->
      propose_transactions_ids = Enum.map(propose.transactions, & &1.id)

      assert Enum.all?(transactions, &(&1.id in propose_transactions_ids))
    end)

    Benchee.run(
      %{
        "propose_new_block" => fn ->
          Kniffel.Blockchain.propose_new_block()
        end
      },
      after_each: fn result ->
        assert {:ok, %Kniffel.Blockchain.Block.Propose{}} = result
      end,
      time: 10,
      memory_time: 2
    )
  end

  @tag :load
  @tag timeout: :infinity
  test "benchmark_commit_to_server" do
    Kniffel.Scheduler.RoundSpecification.set_round_specification(
      Kniffel.Scheduler.RoundSpecification.get_default_round_specification()
    )

    {server_key, server} = create_server(true)
    {_this_server_key, _this_server} = create_this_server()

    block = insert(:block)

    stub(Kniffel.RequestMock, :post, fn _server_url,
                                        %{
                                          block: _propose,
                                          round_specification: _round_specification
                                        } ->
      {:ok,
       %{
         "ok" => "accept"
       }}
    end)

    Benchee.run(
      %{
        "commit_to_server" => fn {server, block} ->
          Kniffel.Blockchain.commit_to_server(server, block)
        end
      },
      after_each: fn result ->
        assert {:ok, "accept"} = result
      end,
      inputs: %{"test" => {server, block}},
      time: 10,
      memory_time: 2
    )
  end

  @tag :load
  @tag timeout: :infinity
  test "benchmark_validate_and_insert_block" do
    transaction_block_limit = Application.get_env(:kniffel, :block_transaction_limit)

    {server_key, server} = create_server(true)
    {_this_server_key, this_server} = create_this_server()
    {user_key, user} = insert_user()

    {:ok, last_block} = Kniffel.Blockchain.genesis()

    timestamp = Timex.now() |> Timex.format!("{ISO:Extended}")
    data = Poison.encode!(%{"games" => [], "scores" => []})

    signature =
      %{data: data, timestamp: timestamp}
      |> Poison.encode!()
      |> Kniffel.Blockchain.Crypto.sign(user_key.private_pem_string)

    transactions =
      insert_list(transaction_block_limit, :not_correct_signed_transaction, %{
        user_id: user.id,
        signature: signature,
        data: data,
        timestamp: timestamp
      })

    propose =
      Map.new()
      |> Map.put(:transactions, transactions)
      |> Map.put(:block, Kniffel.Blockchain.get_last_block())
      |> Map.put(:server, this_server)
      |> Kniffel.Blockchain.Block.Propose.change()

    signature =
      %{hash: Kniffel.Blockchain.Block.Propose.hash(propose), error: :none}
      |> Poison.encode!()
      |> Kniffel.Blockchain.Crypto.sign(server_key.private_pem_string)

    propose_response = %Kniffel.Blockchain.Block.ProposeResponse{
      server_id: server.id,
      hash: Kniffel.Blockchain.Block.Propose.hash(propose),
      signature: signature
    }

    stub(Kniffel.RequestMock, :post, fn _server_url,
                                        %{
                                          block: _propose,
                                          round_specification: _round_specification
                                        } ->
      {:ok,
       %{
         "ok" => "accept"
       }}
    end)

    transaction_data =
      Enum.map(transactions, fn transaction ->
        Map.take(transaction, [:id, :signature, :timestamp, :server_id, :game_id, :data])
      end)

    data =
      Poison.encode!(%{
        "propose" => propose,
        "propose_response" => [propose_response],
        "transactions" => transaction_data
      })

    block = build(:signed_block, %{data: data, block: last_block, transactions: transactions})

    block_params = %{
      "index" => block.index,
      "pre_hash" => block.pre_hash,
      "proof" => block.proof,
      "data" => block.data,
      "hash" => block.hash,
      "signature" => block.signature,
      "timestamp" => block.timestamp,
      "server_id" => block.server_id
    }

    Benchee.run(
      %{
        "validate_and_insert_block" => fn block_params ->
          Kniffel.Blockchain.validate_and_insert_block(block_params)
        end
      },
      after_each: fn result ->
        block = Kniffel.Blockchain.get_last_block()

        assert last_block.index + 1 == block.index
        assert last_block.hash == block.pre_hash
        assert %{ok: :accept} = result

        Repo.update_all(join(Kniffel.Blockchain.Transaction, :inner, [t], b in assoc(t, :block)),
          set: [block_index: nil]
        )

        Repo.delete(block)
      end,
      inputs: %{"test" => block_params},
      time: 10,
      memory_time: 2
    )
  end

  @tag :load
  @tag timeout: :infinity
  test "benchmark_commit_new_block" do
    transaction_block_limit = Application.get_env(:kniffel, :block_transaction_limit)

    Kniffel.Scheduler.RoundSpecification.set_round_specification(
      Kniffel.Scheduler.RoundSpecification.get_default_round_specification()
    )

    {server_key, server} = create_server(true)
    {_this_server_key, this_server} = create_this_server()
    {user_key, user} = insert_user()

    {:ok, last_block} = Kniffel.Blockchain.genesis()

    timestamp = Timex.now() |> Timex.format!("{ISO:Extended}")
    data = Poison.encode!(%{"games" => [], "scores" => []})

    signature =
      %{data: data, timestamp: timestamp}
      |> Poison.encode!()
      |> Kniffel.Blockchain.Crypto.sign(user_key.private_pem_string)

    transactions =
      insert_list(transaction_block_limit, :not_correct_signed_transaction, %{
        user_id: user.id,
        signature: signature,
        data: data,
        timestamp: timestamp
      })

    propose =
      Map.new()
      |> Map.put(:transactions, transactions)
      |> Map.put(:block, last_block)
      |> Map.put(:server, this_server)
      |> Kniffel.Blockchain.Block.Propose.change()

    signature =
      %{hash: Kniffel.Blockchain.Block.Propose.hash(propose), error: :none}
      |> Poison.encode!()
      |> Kniffel.Blockchain.Crypto.sign(server_key.private_pem_string)

    propose_response = %Kniffel.Blockchain.Block.ProposeResponse{
      server_id: server.id,
      hash: Kniffel.Blockchain.Block.Propose.hash(propose),
      signature: signature
    }

    stub(Kniffel.BlockchainMock, :commit_to_server, fn _server, block ->
      nil
    end)

    Benchee.run(
      %{
        "commit_new_block" => fn _input ->
          Kniffel.Blockchain.commit_new_block()
        end
      },
      after_each: fn {:ok, %Kniffel.Blockchain.Block{} = block} ->
        assert last_block.index + 1 == block.index
        assert last_block.hash == block.pre_hash

        Repo.update_all(join(Kniffel.Blockchain.Transaction, :inner, [t], b in assoc(t, :block)),
          set: [block_index: nil]
        )

        Repo.delete(block)
      end,
      before_each: fn _input ->
        Kniffel.Cache.set({:propose, block_index: last_block.index + 1}, propose)

        Kniffel.Cache.set(
          {:propose_response, block_index: last_block.index + 1},
          [propose_response]
        )
      end,
      time: 10,
      memory_time: 2
    )
  end

  @tag :load
  @tag timeout: :infinity
  test "benchmark_finalize_to_server" do
    transaction_block_limit = Application.get_env(:kniffel, :block_transaction_limit)

    {server_key, server} = create_server(true)
    {_this_server_key, this_server} = create_this_server()
    {user_key, user} = insert_user()
    Kniffel.Blockchain.genesis()

    server_age = Kniffel.Scheduler.ServerAge.get_server_age()
    round_specification = Kniffel.Scheduler.RoundSpecification.get_default_round_specification()

    last_block = Kniffel.Blockchain.get_last_block()

    timestamp = Timex.now() |> Timex.format!("{ISO:Extended}")
    data = Poison.encode!(%{"games" => [], "scores" => []})

    signature =
      %{data: data, timestamp: timestamp}
      |> Poison.encode!()
      |> Kniffel.Blockchain.Crypto.sign(user_key.private_pem_string)

    transactions =
      insert_list(transaction_block_limit, :not_correct_signed_transaction, %{
        user_id: user.id,
        signature: signature,
        data: data,
        timestamp: timestamp
      })

    propose =
      Map.new()
      |> Map.put(:transactions, transactions)
      |> Map.put(:block, last_block)
      |> Map.put(:server, this_server)
      |> Kniffel.Blockchain.Block.Propose.change()

    signature =
      %{hash: Kniffel.Blockchain.Block.Propose.hash(propose), error: :none}
      |> Poison.encode!()
      |> Kniffel.Blockchain.Crypto.sign(server_key.private_pem_string)

    propose_response = %Kniffel.Blockchain.Block.ProposeResponse{
      server_id: server.id,
      hash: Kniffel.Blockchain.Block.Propose.hash(propose),
      signature: signature
    }

    transaction_data =
      Enum.map(transactions, fn transaction ->
        Map.take(transaction, [:id, :signature, :timestamp, :server_id, :game_id, :data])
      end)

    data =
      Poison.encode!(%{
        "propose" => propose,
        "propose_response" => [propose_response],
        "transactions" => transaction_data
      })

    block = build(:signed_block, %{data: data, block: last_block, transactions: transactions})

    stub(Kniffel.RequestMock, :post, fn _server_url,
                                        %{
                                          block_height: _block_height,
                                          round_specification: _round_specification,
                                          server_age: _server_age
                                        } ->
      {:ok,
       %{
         "ok" => "accept"
       }}
    end)

    Benchee.run(
      %{
        "finalize_to_server" => fn {block, server, this_server, round_specification, server_age} ->
          Kniffel.Blockchain.finalize_to_server(
            block,
            server,
            this_server,
            round_specification,
            server_age
          )
        end
      },
      after_each: fn result ->
        assert :ok = result
      end,
      inputs: %{"test" => {block, server, this_server, round_specification, server_age}},
      time: 10,
      memory_time: 2
    )
  end

  @tag :load
  @tag timeout: :infinity
  test "benchmark_finalize_block" do
    transaction_block_limit = Application.get_env(:kniffel, :block_transaction_limit)

    {server_key, server} = create_server(true)
    {_this_server_key, this_server} = create_this_server()
    {user_key, user} = insert_user()
    Kniffel.Blockchain.genesis()

    Kniffel.Scheduler.RoundSpecification.set_next_round_specification(
      Kniffel.Scheduler.RoundSpecification.get_default_round_specification()
    )

    server_age = Kniffel.Scheduler.ServerAge.get_server_age(true)

    last_block = Kniffel.Blockchain.get_last_block()

    timestamp = Timex.now() |> Timex.format!("{ISO:Extended}")
    data = Poison.encode!(%{"games" => [], "scores" => []})

    signature =
      %{data: data, timestamp: timestamp}
      |> Poison.encode!()
      |> Kniffel.Blockchain.Crypto.sign(user_key.private_pem_string)

    transactions =
      insert_list(transaction_block_limit, :not_correct_signed_transaction, %{
        user_id: user.id,
        signature: signature,
        data: data,
        timestamp: timestamp
      })

    propose =
      Map.new()
      |> Map.put(:transactions, transactions)
      |> Map.put(:block, last_block)
      |> Map.put(:server, this_server)
      |> Kniffel.Blockchain.Block.Propose.change()

    signature =
      %{hash: Kniffel.Blockchain.Block.Propose.hash(propose), error: :none}
      |> Poison.encode!()
      |> Kniffel.Blockchain.Crypto.sign(server_key.private_pem_string)

    propose_response = %Kniffel.Blockchain.Block.ProposeResponse{
      server_id: server.id,
      hash: Kniffel.Blockchain.Block.Propose.hash(propose),
      signature: signature
    }

    transaction_data =
      Enum.map(transactions, fn transaction ->
        Map.take(transaction, [:id, :signature, :timestamp, :server_id, :game_id, :data])
      end)

    data =
      Poison.encode!(%{
        "propose" => propose,
        "propose_response" => [propose_response],
        "transactions" => transaction_data
      })

    block = insert(:signed_block, %{data: data, block: last_block, transactions: transactions})

    Kniffel.Cache.set({:block, block_index: last_block.index}, block)

    stub(Kniffel.BlockchainMock, :finalize_to_server, fn _block,
                                                         _server,
                                                         _this_server,
                                                         _round_specification,
                                                         _server_age ->
      nil
    end)

    Benchee.run(
      %{
        "finalize_block" => fn ->
          Kniffel.Blockchain.finalize_block()
        end
      },
      after_each: fn result ->
        assert :ok = result
      end,
      time: 10,
      memory_time: 2
    )
  end

  @tag :load
  @tag timeout: :infinity
  test "benchmark_handle_height_change" do
    transaction_block_limit = Application.get_env(:kniffel, :block_transaction_limit)

    {user_key, user} = insert_user()
    {_this_server_key, this_server} = create_this_server()
    {server_key, server} = create_server(true)

    {:ok, genesis} = Kniffel.Blockchain.genesis()
    last_block = insert(:block, %{server_id: server.id, index: 1, pre_hash: genesis.hash})

    server_age = Kniffel.Scheduler.ServerAge.get_server_age(true)

    Kniffel.Scheduler.RoundSpecification.set_round_specification(
      Kniffel.Scheduler.RoundSpecification.get_default_round_specification()
    )

    timestamp = Timex.now() |> Timex.format!("{ISO:Extended}")
    data = Poison.encode!(%{"games" => [], "scores" => []})

    signature =
      %{data: data, timestamp: timestamp}
      |> Poison.encode!()
      |> Kniffel.Blockchain.Crypto.sign(user_key.private_pem_string)

    transactions =
      insert_list(transaction_block_limit, :not_correct_signed_transaction, %{
        user_id: user.id,
        signature: signature,
        data: data,
        timestamp: timestamp
      })

    propose =
      Map.new()
      |> Map.put(:transactions, transactions)
      |> Map.put(:block, last_block)
      |> Map.put(:server, this_server)
      |> Kniffel.Blockchain.Block.Propose.change()

    signature =
      %{hash: Kniffel.Blockchain.Block.Propose.hash(propose), error: :none}
      |> Poison.encode!()
      |> Kniffel.Blockchain.Crypto.sign(server_key.private_pem_string)

    propose_response = %Kniffel.Blockchain.Block.ProposeResponse{
      server_id: server.id,
      hash: Kniffel.Blockchain.Block.Propose.hash(propose),
      signature: signature
    }

    transaction_data =
      Enum.map(transactions, fn transaction ->
        Map.take(transaction, [:id, :signature, :timestamp, :server_id, :game_id, :data])
      end)

    data =
      Poison.encode!(%{
        "propose" => propose,
        "propose_response" => [propose_response],
        "transactions" => transaction_data
      })

    block = insert(:signed_block, %{data: data, block: last_block, transactions: transactions})

    Benchee.run(
      %{
        "handle_height_change" => fn params ->
          Kniffel.Blockchain.handle_height_change(params)
        end
      },
      after_each: fn result ->
        assert {:ok, :accept} = result
      end,
      inputs: %{
        "test" => %{"server_id" => this_server.id, "hash" => block.hash, "index" => block.index}
      },
      time: 10,
      memory_time: 2
    )
  end
end
