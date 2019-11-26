defmodule KniffelWeb.ServerController do
  use KniffelWeb, :controller

  alias Kniffel.Server

  def index(conn, _params) do
    servers = Server.get_servers()
    render(conn, "index.json", servers: servers)
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
