defmodule KniffelWeb.ServerController do
  use KniffelWeb, :controller

  alias Kniffel.Server

  def index(conn, _params) do
    servers = Server.get_servers()
    render(conn, "index.json", servers: servers)
  end

  def this(conn, _params) do
    server = Server.get_this_server()
    render(conn, "show.json", server: server)
  end

  def show(conn, %{"id" => server_id}) do
    server = Server.get_server(server_id)
    render(conn, "show.json", server: server)
  end

  def roll(conn, attrs) do
    with dices <- attrs["dices_to_roll"] || [],
         true <- is_list(dices),
         n when n > 0 <-
           length(dices) do
      dices = Server.roll_dices(dices)
      json(conn, dices)
    else
      false ->
        json(conn, %{error: "no dices_to_roll specified"})

      0 ->
        json(conn, %{error: "no dices_to_roll specified"})
    end
  end

  def create(conn, %{"server" => %{"url" => url} = server}) do
    case Server.get_server_by_url(url) do
      %Server{} ->
        json(conn, %{ok: "Server already known."})

      nil ->
        case Server.create_server(server) do
          {:ok, server} ->
            render(conn, "show.json", server: server)

          {:error, message} ->
            json(conn, %{error: message})
        end
    end
  end
end
