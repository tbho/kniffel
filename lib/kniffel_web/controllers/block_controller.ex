defmodule KniffelWeb.BlockController do
  use KniffelWeb, :controller

  alias Kniffel.{Blockchain, Blockchain.Block.Propose}

  def index(conn, _params) do
    blocks = Blockchain.get_blocks()
    render(conn, "index.json", blocks: blocks)
  end

  def show(conn, %{"id" => block_id}) do
    block = Blockchain.get_block(block_id)
    render(conn, "show.json", block: block)
  end

  def create(conn, %{"block" => block_params}) do
    case Blockchain.insert_block(block_params) do
      {:ok, block} ->
        render(conn, "show.json", block: block)

      {:error, message} ->
        json(conn, %{error: message})
    end
  end

  def propose(conn, %{"propose" => propose}) do
    data =
      propose
      |> Propose.change()
      |> Blockchain.validate_block_proposal()

    json(conn, data)
  end
end
