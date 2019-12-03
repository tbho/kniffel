defmodule KniffelWeb.ServerController do
  use KniffelWeb, :controller

  alias Kniffel.Server
  alias Kniffel.Blockchain.Crypto

  def index(conn, _params) do
    servers = Server.get_servers()
    render(conn, "index.json", servers: servers)
  end

  def this(conn, _params) do
    {:ok, private_key} = Crypto.private_key
    {:ok, public_key} = ExPublicKey.public_key_from_private_key(private_key)
    server_id = ExPublicKey.RSAPublicKey.get_fingerprint(public_key)

    server = Server.get_server(server_id)
    render(conn, "show.json", server: server)
  end

  def show(conn, %{"id" => server_id}) do
    server = Server.get_server(server_id)
    render(conn, "show.json", server: server)
  end

  def create(conn, %{"server" => server}) do
    case Server.create_server(server) do
      {:ok, server} ->
        render(conn, "show.json", server: server)

      {:error, message} ->
        json(conn, %{error: message})
    end
  end
end
