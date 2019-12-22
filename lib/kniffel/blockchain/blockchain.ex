defmodule Kniffel.Blockchain do
  @moduledoc """
  Blockchain Module to controll and insert data into it.
  """

  import Ecto.Query, warn: false

  alias Kniffel.Repo
  alias Kniffel.Blockchain.{Block, Block.Propose, Block.ServerResponse, Transaction}
  alias Kniffel.{Game, Game.Score, User, Server}

  @block_transaction_limit 10
  @active_server_treshhold 10

  @age_calculation_select_limit 10

  # -----------------------------------------------------------------
  # -- Block
  # -----------------------------------------------------------------
  def get_blocks() do
    Block
    |> order_by(desc: :index)
    |> Repo.all()
  end

  def get_block(index) do
    Block
    |> Repo.get(index)
  end

  def genesis() do
    block_params = %{
      data: Poison.encode!("So it begins! - King Théoden"),
      pre_hash: "ZERO_HASH",
      index: 0,
      transactions: []
    }

    %Block{}
    |> Repo.preload([:server])
    |> Block.changeset_create(block_params)
    |> Repo.insert()
  end

  def get_last_block() do
    Block
    |> order_by(desc: :index)
    |> limit(1)
    |> Repo.one()
  end

  def get_block_data_ids() do
    get_block_data_query()
    |> select([t], t.id)
    |> Repo.all()
  end

  def get_block_data() do
    get_block_data_query()
    |> Repo.all()
  end

  defp get_block_data_query() do
    Transaction
    |> where([t], is_nil(t.block_index))
    |> order_by(asc: :timestamp)
    |> limit(@block_transaction_limit)
  end

  def propose_new_block() do
    if length(get_block_data()) > 0 do
      propose =
        Map.new()
        |> Map.put(:transactions, get_block_data())
        |> Map.put(:block, get_last_block())
        |> Map.put(:server, Server.get_this_server())
        |> Propose.change()

      Kniffel.Cache.delete({:propose, block_index: propose.block_index})
      Kniffel.Cache.delete({:propose_response, block_index: propose.block_index})

      Kniffel.Cache.set({:propose, block_index: propose.block_index}, propose)

      Server.get_authorized_servers(false)
      |> Enum.map(fn server ->
        {:ok, response} =
          HTTPoison.post(
            server.url <> "/api/blocks/#{propose.block_index}/propose",
            Poison.encode!(%{propose: propose}),
            [
              {"Content-Type", "application/json"}
            ]
          )

        with %{"propose_response" => propose_response} <- Poison.decode!(response.body),
             %ServerResponse{} = propose_response <- ServerResponse.change(propose_response),
             {:ok, propose_response} <- ServerResponse.verify(propose, propose_response),
             true <- propose_response.server_id == server.id do
          results = Kniffel.Cache.get({:propose_response, block_index: propose.block_index}) || []

          Kniffel.Cache.set(
            {:propose_response, block_index: propose.block_index},
            [propose_response] ++ results
          )

          propose_response
        else
          false ->
            {:error, :server_id_does_not_match}

          {:error, message} ->
            {:error, message}
        end
      end)
    else
      {:error, :no_transactions_for_block}
    end
  end

  def validate_block_proposal(%Propose{} = propose) do
    with {:ok, propose} <- Propose.verify(propose),
         transactions <- get_proposal_transactions(propose),
         block_data_ids <- get_block_data_ids(),
         true <- Enum.map(transactions, & &1.id) |> Enum.sort() == block_data_ids |> Enum.sort() do
      propose_response =
        Map.new()
        |> Map.put(:propose, propose)
        |> Map.put(:server, Server.get_this_server())
        |> ServerResponse.change()

      Kniffel.Cache.set(
        %{block_index: propose.block_index, server_id: propose.server_id},
        %{propose: propose, propose_response: propose_response}
      )

      propose_response
    else
      {:error, message} ->
        Map.new()
        |> Map.put(:error, message)
        |> Map.put(:server, Server.get_this_server())
        |> ServerResponse.change()

      false ->
        Map.new()
        |> Map.put(:error, :oldest_transaction_are_not_in_block)
        |> Map.put(:server, Server.get_this_server())
        |> ServerResponse.change()
    end
  end

  def get_proposal_transactions(%Propose{} = propose) do
    server = Server.get_server(propose.server_id)

    Enum.map(propose.transactions, fn propose_transaction ->
      %Transaction{} =
        transaction =
        case get_transaction(propose_transaction.id) do
          %Transaction{} = transaction ->
            transaction

          nil ->
            get_transaction_from_server(propose_transaction.id, server.url)
        end

      true = transaction.signature == propose_transaction.signature
      true = DateTime.to_string(transaction.timestamp) == propose_transaction.timestamp

      transaction
    end)
    |> Enum.sort(&(&1.timestamp < &2.timestamp))
  end

  def create_new_block() do
    last_block = get_last_block()

    propose = Kniffel.Cache.get({:propose, block_index: last_block.index + 1})

    propose_response = Kniffel.Cache.get({:propose_response, block_index: last_block.index + 1})

    if !is_nil(propose) do
      true = propose.pre_hash == last_block.hash
      true = propose.block_index == last_block.index + 1
      true = propose.server_id == Server.get_this_server().id

      propose_response_count =
        Enum.filter(propose_response, &(&1.error == :none)) ||
          []
          |> length

      true = propose_response_count >= calculate_min_propose_response_count

      transactions = get_block_data()

      true =
        Enum.map(transactions, & &1.id) |> Enum.sort() ==
          Enum.map(propose.transactions, & &1.id) |> Enum.sort()

      transaction_data =
        Enum.map(transactions, fn transaction ->
          Map.take(transaction, [:id, :signature, :timestamp, :server_id, :game_id, :data])
        end)

      data =
        Poison.encode!(%{
          "propose_response" => propose_response,
          "transactions" => transaction_data
        })

      block_params = %{
        data: data,
        transactions: transactions,
        index: last_block.index + 1,
        pre_hash: last_block.hash
      }

      {:ok, block} =
        %Block{}
        |> Repo.preload([:server])
        |> Block.changeset_create(block_params)
        |> Repo.insert()

      servers = Server.get_authorized_servers(false)

      Enum.map(servers, fn server ->
        {:ok, response} = HTTPoison.post(
          server.url <> "/api/blocks",
          Poison.encode!(%{block: Block.json_encode(block)}),
          [
            {"Content-Type", "application/json"}
          ]
        )
        IO.inspect(Poison.decode(response.body))
      end)

      {:ok, block}
    else
      {:error, :no_propose_for_block}
    end
  end

  def insert_block(%{"server_id" => server_id, "data" => data, "index" => index} = block_params) do
    %{propose: propose, propose_response: _} =
      Kniffel.Cache.get(%{block_index: index, server_id: server_id})

    with %{"propose_response" => propose_responses, "transactions" => transaction_data} <-
           Poison.decode!(data),
         %Server{authority: true} = server <- Server.get_server(server_id),
         nil <- get_block(index) do
      transactions =
        Enum.map(transaction_data, fn transaction_params ->
          transaction = get_transaction(transaction_params["id"])

          case transaction do
            %Transaction{} = transaction ->
              if transaction.signature == transaction_params["signature"] do
                transaction
              else
                {:transaction_signature, "already known transaction does not match signature"}
              end

            nil ->
              {:ok, %{body: %{transaction: transaction_params}}} =
                HTTPoison.get(server.url <> "/api/transactions/#{transaction_params["id"]}")

              {:ok, transaction} = insert_transaction(transaction_params)
              transaction
          end
        end)

      true =
        Enum.map(transactions, & &1.id) |> Enum.sort() ==
          Enum.map(propose.transactions, & &1.id) |> Enum.sort()

      true = propose.pre_hash == block_params["pre_hash"]
      true = propose.block_index == block_params["index"]
      true = propose.server_id == server.id

      propose_response_count =
        Enum.map(propose_responses, fn propose_response_params ->
          propose_response =
            propose_response_params
            |> ServerResponse.change()

          ServerResponse.verify(propose, propose_response)
        end)
        |> Enum.count(&(%ServerResponse{} = &1))

      true = propose_response_count >= calculate_min_propose_response_count

      block_params =
        block_params
        |> Map.drop(["transactions"])
        |> Map.put("server", server)
        |> Map.put("transactions", transactions)

      {:ok, block} =
        %Block{}
        |> Repo.preload([:server, :transactions])
        |> Block.changeset_p2p(block_params)
        |> Repo.insert()

      Map.new()
      |> Map.put(:block, block)
      |> Map.put(:server, Server.get_this_server())
      |> ServerResponse.change()
    else
      %Block{} = block ->
        {:index_blocked, block}

      nil ->
        {:unknown_server, server_id}
    end
  end

  def calculate_ages_of_servers() do
    servers = Server.get_authorized_servers()
    calculate_ages_of_servers(0, @age_calculation_select_limit, servers)
  end

  def calculate_ages_of_servers(offset, limit, servers, result \\ %{}) do
    blocks =
      Block
      |> order_by(desc: :index)
      |> limit(^limit)
      |> offset(^offset)
      |> Repo.all()

    {result, offset} =
      Enum.reduce(blocks, {result, offset}, fn block, {result, offset} ->
        {Map.put_new(result, block.server_id, offset), offset + 1}
      end)

    if Enum.all?(servers, fn server -> Map.get(result, server.id) != nil end) do
      result
    else
      calculate_ages_of_servers(offset, limit, servers, result)
    end
  end

  def get_active_servers() do
    blocks =
      Block
      |> order_by(desc: :index)
      |> limit(@active_server_treshhold)
      |> Repo.all()

    Enum.reduce(blocks, [], fn block, result ->
      if block.index != 0 do
        %{"propose_response" => propose_responses} = Poison.decode!(block.data)

        Enum.uniq(
          result ++ Enum.map(propose_responses, &([&1["server_id"]] ++ [block.server_id]))
        )
      end
    end)

    ["dab28baffc1e390792f1506ac9cc733fba8fed887e187a1bf61bba1193de0f86"]
  end

  def calculate_min_propose_response_count() do
    twothirds = length(get_active_servers) / 3 * 2
    if twothirds < 1, do: 1, else: Kernel.trunc(twothirds)
  end

  # -----------------------------------------------------------------
  # -- Transaction
  # -----------------------------------------------------------------
  def get_transactions() do
    from(t in Transaction)
    |> order_by(asc: :timestamp)
    |> Repo.all()
  end

  def get_transaction(id) do
    Transaction
    |> Repo.get(id)
  end

  def get_transaction_from_server(id, server_url) do
    {:ok, response} =
      HTTPoison.get(server_url <> "/api/transactions/#{id}")
    %{"transaction" => transaction_params} = Poison.decode!(response.body)

    {:ok, transaction} = insert_transaction(transaction_params)
    transaction
  end

  def data_for_transaction?(user_id) do
    scores =
      user_id
      |> score_query_for_transaction
      |> Repo.aggregate(:count, :id)

    games =
      user_id
      |> game_query_for_transaction
      |> Repo.aggregate(:count, :id)

    games > 0 || scores > 0
  end

  defp get_transaction_data(user_id) do
    scores =
      user_id
      |> score_query_for_transaction
      |> Repo.all()

    games =
      user_id
      |> game_query_for_transaction
      |> Repo.all()

    {games, scores}
  end

  defp score_query_for_transaction(user_id) do
    Score
    |> where([s], is_nil(s.transaction_id))
    |> where([s], s.user_id == ^user_id)
    |> where([s], s.score_type != "none")
    |> order_by(asc: :inserted_at)
  end

  defp game_query_for_transaction(user_id) do
    Game
    |> preload(:users)
    |> where([g], is_nil(g.transaction_id))
    |> where([g], g.user_id == ^user_id)
  end

  def create_transaction(transaction_params, user) do
    {games, scores} = get_transaction_data(user.id)

    if length(games) > 0 || length(scores) > 0 do
      score_data =
        Enum.map(scores, fn score ->
          Map.take(score, [
            :dices,
            :score_type,
            :id,
            :predecessor_id,
            :user_id,
            :game_id,
            :inserted_at,
            :signature,
            :server_id
          ])
        end)

      game_data =
        Enum.map(games, fn game ->
          users =
            Enum.map(game.users, fn user ->
              Map.get(user, :id)
            end)

          Map.take(game, [:user_id, :inserted_at, :id])
          |> Map.put(:users, users)
        end)

      data = Poison.encode!(%{"scores" => score_data, "games" => game_data})

      transaction_params =
        transaction_params
        |> Map.drop(["user"])
        |> Map.put("user", user)
        |> Map.put("data", data)
        |> Map.put("games", games)
        |> Map.put("scores", scores)

      {:ok, transaction} =
        %Transaction{}
        |> Repo.preload([:user, :block])
        |> Transaction.changeset_create(transaction_params)
        |> Repo.insert()

      servers = Server.get_servers(false)

      Enum.map(servers, fn server ->
        HTTPoison.post(
          server.url <> "/api/transactions",
          Poison.encode!(%{transaction: Transaction.json_encode(transaction)}),
          [
            {"Content-Type", "application/json"}
          ]
        )
      end)

      {:ok, transaction}
    else
      {:error, :no_data_for_transaction}
    end
  end

  def insert_transaction(%{"user_id" => user_id, "data" => data} = transaction_params) do
    data = Poison.decode!(data)

    user = User.get_user(user_id)

    games =
      Enum.map(data["games"], fn game ->
        users = Enum.map(game["users"] || [], &User.get_user(&1))
        Map.put(game, "users", users)
      end)

    block_index = transaction_params["block_index"] || nil

    block =
      case block_index do
        nil ->
          nil

        block_index ->
          get_block(block_index)
      end

    transaction_params =
      transaction_params
      |> Map.drop(["user_id", "block_index"])
      |> Map.put("user", user)
      |> Map.put("block", block)
      |> Map.put("scores", data["scores"])
      |> Map.put("games", games)

    %Transaction{}
    |> Repo.preload([:user, :block])
    |> Transaction.changeset_p2p(transaction_params)
    |> Repo.insert()
  end

  # @doc "Validate the complete blockchain"
  # def valid?(blockchain) when is_list(blockchain) do
  #   zero =
  #     Enum.reduce_while(blockchain, nil, fn prev, current ->
  #       cond do
  #         current == nil ->
  #           {:cont, prev}

  #         Block.valid?(current, prev) ->
  #           {:cont, prev}

  #         true ->
  #           {:halt, false}
  #       end
  #     end)

  #   if zero, do: Block.valid?(zero), else: false
  # end
end
