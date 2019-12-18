defmodule Kniffel.Blockchain do
  @moduledoc """
  Blockchain Module to controll and insert data into it.
  """

  import Ecto.Query, warn: false

  alias Kniffel.Repo
  alias Kniffel.Blockchain.{Block, Block.Propose, Transaction, Crypto}
  alias Kniffel.{Game, Game.Score, User, Server}

  @block_transaction_limit 10

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
    propose =
      Map.new()
      |> Map.put(:transactions, get_block_data())
      |> Map.put(:block, get_last_block())
      |> Map.put(:server, Server.get_this_server())
      |> Propose.change()

    servers = Server.get_servers()

    Enum.map(servers, fn server ->
      {:ok, response} =
        HTTPoison.post(
          server.url <> "/api/blocks/#{propose.block_index}/propose",
          Poison.encode!(%{propose: propose}),
          [
            {"Content-Type", "application/json"}
          ]
        )

      data =
        case Poison.decode!(response.body) do
          %{"hash" => hash, "server_id" => server_id, "signature" => signature} ->
            true = server_id == propose.server_id
            true = hash == Propose.hash(propose)

            signature_response_status =
              hash
              |> Poison.encode!()
              |> Crypto.verify(server.public_key, signature)

            case signature_response_status do
              :ok ->
                %{hash: hash, signature: signature}

              :invalid ->
                %{message: :signature_invalid}
            end

          %{"error" => message} ->
            %{message: message}
        end

      Kniffel.Cache.set(%{block_index: propose.block_index, server_id: server.id}, data)
      data
    end)
  end

  def validate_block_proposal(%Propose{} = propose) do
    with {:ok, propose} <- Propose.verify(propose),
         transactions <- get_proposal_transactions(propose),
         block_data_ids <- get_block_data_ids(),
         true <- Enum.map(transactions, & &1.id) == block_data_ids,
         {:ok, private_key} <- Crypto.private_key(),
         {:ok, private_key_pem} <- ExPublicKey.pem_encode(private_key),
         hash <- Propose.hash(propose),
         hash_enc <- Poison.encode!(hash),
         signature <- Crypto.sign(hash_enc, private_key_pem),
         %Server{} = server <- Server.get_this_server() do
      Kniffel.Cache.set(
        %{block_index: propose.block_index, server_id: propose.server_id},
        propose
      )

      %{server_id: server.id, signature: signature, hash: hash}
    else
      {:error, message} ->
        %{error: message}

      false ->
        %{error: :oldest_transaction_are_not_in_block}
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
    transactions = get_block_data()

    if length(transactions) > 0 do
      transaction_data =
        Enum.map(transactions, fn transaction ->
          Map.take(transaction, [:id, :signature, :timestamp, :server_id, :game_id, :data])
        end)

      data = Poison.encode!(%{"transactions" => transaction_data})

      last_block = get_last_block()

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

      servers = Server.get_other_servers()

      Enum.map(servers, fn server ->
        HTTPoison.post(
          server.url <> "/api/blocks",
          Poison.encode!(%{block: Block.json_encode(block)}),
          [
            {"Content-Type", "application/json"}
          ]
        )
      end)

      {:ok, block}
    else
      {:error, :no_transactions_for_block}
    end
  end

  def insert_block(%{"server_id" => server_id, "data" => data, "index" => index} = block_params) do
    with data <- Poison.decode!(data),
         %Server{authority: true} = server <- Server.get_server(server_id),
         nil <- get_block(index) do
      transactions =
        Enum.map(data["transactions"], fn transaction_params ->
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

      block_params =
        block_params
        |> Map.drop(["transactions"])
        |> Map.put("server", server)
        |> Map.put("transactions", transactions)

      %Block{}
      |> Repo.preload([:server, :transactions])
      |> Block.changeset_p2p(block_params)
      |> Repo.insert()
    else
      %Block{} = block ->
        {:index_blocked, block}

      nil ->
        {:unknown_server, server_id}
    end
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
    {:ok, %{body: %{transaction: transaction_params}}} =
      HTTPoison.get(server_url <> "/api/transactions/#{id}")

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

      servers = Server.get_other_servers()

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
