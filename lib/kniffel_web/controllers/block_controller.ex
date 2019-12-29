defmodule KniffelWeb.BlockController do
  use KniffelWeb, :controller

  alias Kniffel.{Blockchain, Blockchain.Block.Propose, Blockchain.Block.ServerResponse, Server}

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

  def finalize(conn, %{"block_height" => height_params}) do
    {:ok, block} = Blockchain.handle_height_change(height_params)
    render(conn, "show.json", block: block)
  end

  def height(conn, _attrs) do
    server = Server.get_this_server()
    block = Blockchain.get_last_block()

    json(conn, %{
      height_response: %{
        height: block.index,
        timestamp: Timex.format!(block.timestamp, "{ISO:Extended}"),
        server_id: server.id,
        hash: block.hash
      }
    })
  end
end
