defmodule KniffelWeb.BlockController do
  use KniffelWeb, :controller

  alias Kniffel.{Blockchain, Blockchain.Crypto, Server}

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

  def propose(
        conn,
        %{
          "id" => block_id,
          "transactions" => transaction_params,
          "signature" => signature,
          "server_id" => server_id
        } = attrs
      ) do
    Blockchain.validate_block_proposal(transaction_params, signature, block_id, server_id)

    {:ok, private_key} = Crypto.private_key()
    {:ok, private_key_pem} = ExPublicKey.pem_encode(private_key)

    signature =
      attrs
      |> Poison.encode!()
      |> Crypto.sign(private_key_pem)

    server = Server.get_this_server()
    json(conn, %{server_id: server.id, signature: signature})
  end
end
