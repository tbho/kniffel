defmodule Kniffel.Server do
  use Ecto.Schema

  import Ecto.Query, warn: false
  import Ecto.Changeset

  alias Kniffel.{
    Repo,
    Server,
    Blockchain.Crypto
  }

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "server" do
    field :url, :string
    field :public_key, :string
    field :authority, :boolean, default: false

    timestamps()
  end

  @doc false
  def changeset(server, attrs = %{"public_key" => public_key_string}) do
    {:ok, public_key} = ExPublicKey.loads(public_key_string)
    {:ok, public_key_pem} = ExPublicKey.pem_encode(public_key)

    id = ExPublicKey.RSAPublicKey.get_fingerprint(public_key)

    attrs =
      attrs
      |> Map.put("public_key", public_key_pem)
      |> Map.put("id", id)

    server
    |> cast(attrs, [:id, :url, :public_key, :authority])
  end

  # -----------------------------------------------------------------
  # -- Server
  # -----------------------------------------------------------------

  def get_servers() do
    Repo.all(Server)
  end

  def get_other_servers() do
    this_server = get_this_server()

    Server
    |> where([s], s.id != ^this_server.id)
    |> Repo.all()
  end

  def get_authorized_server() do
    this_server = get_this_server()

    if this_server.authority do
      this_server
    else
      authorized_server_query
      |> limit(1)
      |> Repo.one()
    end
  end

  def get_authorized_servers() do
    this_server = get_this_server()

    authorized_server_query
    |> where([s], s.id != ^this_server.id)
    |> Repo.all()
  end

  defp authorized_server_query() do
    Server
    |> where([s], s.authority == true)
  end

  def get_server(id) do
    Repo.get(Server, id)
  end

  def get_server_by_url(url) do
    Repo.get_by(Server, url: url)
  end

  def get_this_server() do
    case Kniffel.Cache.get(:server) do
      %Server{} = server ->
        server

      nil ->
        {:ok, private_key} = Crypto.private_key()
        {:ok, public_key} = ExPublicKey.public_key_from_private_key(private_key)
        server_id = ExPublicKey.RSAPublicKey.get_fingerprint(public_key)

        server = Server.get_server(server_id)
        Kniffel.Cache.set(:server, server)
        server
    end
  end

  def get_oldest_server() do
    case Kniffel.Cache.get(:server) do
      %Server{} = server ->
        server

      nil ->
        {:ok, private_key} = Crypto.private_key()
        {:ok, public_key} = ExPublicKey.public_key_from_private_key(private_key)
        server_id = ExPublicKey.RSAPublicKey.get_fingerprint(public_key)

        server = Server.get_server(server_id)
        Kniffel.Cache.set(:server, server)
        server
    end
  end

  def create_server(%{"url" => url}) do
    {:ok, response} = HTTPoison.get(url <> "/api/servers/this")
    {:ok, server} = Poison.decode(response.body)

    {:ok, server} =
      %Server{}
      |> Server.changeset(server["server"])
      |> Repo.insert()

    {:ok, _response} =
      HTTPoison.post(
        server.url <> "/api/servers",
        Poison.encode!(%{server: %{url: Server.get_this_server().url}}),
        [
          {"Content-Type", "application/json"}
        ]
      )

    {:ok, server}
  end

  def update_server(server, server_params) do
    server
    |> Server.changeset(server_params)
    |> Repo.update()
  end

  def delete_server(server) do
    Repo.delete(server)
  end

  def change_server(server \\ %Server{}, attrs \\ %{}) do
    changeset(server, attrs)
  end

  def roll_dices(dices_to_roll) do
    with {:ok, private_key} <- Crypto.private_key(),
         {:ok, private_key_pem} <- ExPublicKey.pem_encode(private_key) do
      dices =
        dices_to_roll
        |> Enum.map(fn x ->
          {x, :rand.uniform(6)}
        end)
        |> Map.new()

      timestamp = DateTime.to_string(DateTime.truncate(DateTime.utc_now(), :second))

      signature =
        Poison.encode!(%{"dices" => dices, "timestamp" => timestamp})
        |> Crypto.sign(private_key_pem)

      server = get_this_server()

      %{dices: dices, signature: signature, server_id: server.id, timestamp: timestamp}
    end
  end
end
