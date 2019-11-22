defmodule Kniffel.Blockchain do
  @moduledoc """
  Blockchain Module to controll and insert data into it.
  """

  import Ecto.Query, warn: false

  alias Kniffel.Repo
  alias Kniffel.Blockchain.Block
  alias Kniffel.Blockchain.Transaction
  alias Kniffel.Blockchain.Crypto
  alias Kniffel.{Game, Game.Score}

  require Logger

  # -----------------------------------------------------------------
  # -- Block
  # -----------------------------------------------------------------
  def get_blockchain() do
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
    |> Repo.preload([:user])
    |> Block.changeset_create(block_params)
    |> IO.inspect()
    |> Repo.insert()
  end

  def get_last_block() do
    Block
    |> order_by(desc: :index)
    |> limit(1)
    |> Repo.one()
  end

  def get_block_data() do
    Transaction
    |> where([t], is_nil(t.block_index))
    |> Repo.all()
  end

  def create_new_block() do
    transactions = get_block_data()

    if length(transactions) > 0 do
      transaction_data =
        Enum.map(transactions, fn transaction ->
          Map.take(transaction, [:id ,:signature, :timestamp, :user_id, :game_id])
        end)

      data = Poison.encode!(%{"transactions" => transaction_data})

      last_block = get_last_block()

      block_params = %{
        data: data,
        transactions: transactions,
        index: last_block.index + 1,
        pre_hash: last_block.hash
      }

      %Block{}
      |> Repo.preload([:user])
      |> Block.changeset_create(block_params)
      |> IO.inspect()
      |> Repo.insert()
    else
      {:error, :no_transactions_for_block}
    end
  end

  # def insert_block(attrs) do
  #   %Block{}
  #   |> Block.changeset_p2p(attrs)
  #   |> Repo.insert()
  # end

  # -----------------------------------------------------------------
  # -- Transaction
  # -----------------------------------------------------------------
  def get_transactions() do
    from(t in Transaction)
    |> Repo.all()
  end

  def get_transaction(index) do
    Transaction
    |> Repo.get(index)
  end

  # def get_transaction_data(user_id) do
  #   scores =
  #     Score
  #     |> where([s], is_nil(s.transaction_id))
  #     |> where([s], s.user_id == ^user_id)
  #     |> where([s], s.score_type != "none")
  #     |> select([s], %{
  #       dices: s.dices,
  #       score_type: s.score_type,
  #       id: s.id,
  #       predecessor_id: s.predecessor_id,
  #       user_id: s.user_id,
  #       game_id: s.game_id
  #     })
  #     |> Repo.all()
  #     |> Enum.map(fn score ->
  #       Map.take(score, [:dices, :score_type, :id, :predecessor_id, :user_id, :game_id])
  #     end)

  #   games =
  #     Game
  #     |> preload(:users)
  #     |> where([g], is_nil(g.transaction_id))
  #     |> where([g], g.user_id == ^user_id)
  #     |> Repo.all()
  #     |> Enum.map(fn game ->
  #       users =
  #         Enum.map(game.users, fn user ->
  #           Map.get(user, :id)
  #         end)

  #       Map.take(game, [:user_id, :inserted_at, :id])
  #       |> Map.put(:users, users)
  #     end)

  #   data = Poison.encode!(%{"scores" => scores, "games" => games})
  #   %{"data" => data}
  # end

  def get_transaction_data(user_id) do
    scores =
      Score
      |> where([s], is_nil(s.transaction_id))
      |> where([s], s.user_id == ^user_id)
      |> where([s], s.score_type != "none")
      |> Repo.all()

    games =
      Game
      |> preload(:users)
      |> where([g], is_nil(g.transaction_id))
      |> where([g], g.user_id == ^user_id)
      |> Repo.all()

    {games, scores}
  end

  def create_transaction(transaction_params, user) do
    {games, scores} = get_transaction_data(user.id)

    if length(games) > 0 || length(scores) > 0 do
      score_data =
        Enum.map(scores, fn score ->
          Map.take(score, [:dices, :score_type, :id, :predecessor_id, :user_id, :game_id])
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

      %Transaction{}
      |> Repo.preload([:user, :block])
      |> Transaction.changeset_create(transaction_params)
      |> Repo.insert()
    else
      {:error, :no_data_for_transaction}
    end
  end

  # def insert_transaction(transaction_params) do
  #   %Transaction{}
  #   |> Transaction.changeset_p2p(transaction_params)
  #   |> Repo.insert()
  # end

  @doc "Validate the complete blockchain"
  def valid?(blockchain) when is_list(blockchain) do
    zero =
      Enum.reduce_while(blockchain, nil, fn prev, current ->
        cond do
          current == nil ->
            {:cont, prev}

          Block.valid?(current, prev) ->
            {:cont, prev}

          true ->
            {:halt, false}
        end
      end)

    if zero, do: Block.valid?(zero), else: false
  end
end
