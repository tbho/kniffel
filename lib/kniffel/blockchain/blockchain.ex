defmodule Kniffel.Blockchain do
  @moduledoc """
  Blockchain Module to controll and insert data into it.
  """

  import Ecto.Query, warn: false

  alias Kniffel.Repo
  alias Kniffel.Blockchain.Block
  alias Kniffel.Blockchain.Transaction
  alias Kniffel.Blockchain.Crypto

  require Logger

  # -----------------------------------------------------------------
  # -- Block
  # -----------------------------------------------------------------
  def get_blockchain() do
    from(b in Block, order_by: [b.index])
    |> Repo.all()
  end

  def get_block(index) do
    Block
    |> Repo.get(index)
  end

  def create_new_block(block_params) do
    %Block{}
    |> Block.changeset_create(block_params)
    |> Repo.insert()
  end

  def insert_block(attrs) do
    %Block{}
    |> Block.changeset_p2p(attrs)
    |> Repo.insert()
  end

  # -----------------------------------------------------------------
  # -- Transaction
  # -----------------------------------------------------------------
  def get_transactions(filter) do
    from(t in Transaction)
    |> Repo.all()
  end

  def get_transaction(index) do
    Transaction
    |> Repo.get(index)
  end

  def create_transaction(transaction_params, user) do
    %Transaction{}
    |> Transaction.changeset_create(transaction_params, user)
    |> Repo.insert()
  end

  def insert_transaction(transaction_params) do
    %Transaction{}
    |> Transaction.changeset_p2p(transaction_params)
    |> Repo.insert()
  end

  def get_data(blockchain, filter) when is_list(blockchain) do
    Enum.filter(blockchain, filter)
  end

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
