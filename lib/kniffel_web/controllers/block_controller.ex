defmodule KniffelWeb.BlockController do
  use KniffelWeb, :controller

  alias Kniffel.Blockchain

  def show(conn, %{"id" => block_id}) do
    block = Blockchain.get_block(block_id)

    render(conn, "show.json", block: block)
  end
end
