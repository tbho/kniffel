defmodule KniffelWeb.BlockController do
  use KniffelWeb, :controller

  alias Kniffel.{Blockchain, Blockchain.Block.Propose, Blockchain.Block.ServerResponse}

  def index(conn, _params) do
    blocks = Blockchain.get_blocks()
    render(conn, "index.json", blocks: blocks)
  end

  def show(conn, %{"id" => block_id}) do
    block = Blockchain.get_block(block_id)
    render(conn, "show.json", block: block)
  end

  def propose(conn, %{"propose" => propose}) do
    propose_response =
      propose
      |> Propose.change()
      |> Blockchain.validate_block_proposal()

    json(conn, %{propose_response: ServerResponse.json(propose_response)})
  end

  def commit(conn, %{"block" => block_params}) do
    block_response = Blockchain.insert_block(block_params)
    json(conn, %{block_response: ServerResponse.json(block_response)})
  end

  def finalize(conn, %{"block" => block_params}) do
    {:ok, block} = Blockchain.insert_block_from_network(block_params)
    render(conn, "show.json", block: block)
  end
end
