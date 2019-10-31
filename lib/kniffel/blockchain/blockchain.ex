defmodule Kniffel.Blockchain do
  @moduledoc """
  Documentation for BaPoc.
  """

  @doc """
  Hello world.

  ## Examples

      iex> BaPoc.hello()
      :world

  """
  alias Kniffel.Blockchain.Block
  alias Kniffel.Blockchain.Crypto

  @doc "Create a new blockchain with a zero block"
  def new do
    [Crypto.hash!(Block.genesis())]
  end

  @doc "Insert given data as a new block in the blockchain"
  def insert(blockchain, data, key) when is_list(blockchain) do
    %Block{hash: prev, index: index} = List.last(blockchain)

    block =
      data
      |> Block.new(prev, index + 1 )
      |> Crypto.sign!(key)
      |> Crypto.hash!()

    [block | blockchain]
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
