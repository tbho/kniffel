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

  @server_white_list ["https://kniffel.app", "http://hoge.cloud:3000"]

  schema "server" do
    field :url, :string
    field :public_key, :string
    field :authority, :boolean, default: false

    timestamps()
  end

  @doc false
  def changeset(server, attrs = %{"public_key" => public_key_string, "url" => url}) do
    {:ok, public_key} = ExPublicKey.loads(public_key_string)
    {:ok, public_key_pem} = ExPublicKey.pem_encode(public_key)

    id = ExPublicKey.RSAPublicKey.get_fingerprint(public_key)

    attrs =
      attrs
      |> Map.put("public_key", public_key_pem)
      |> Map.put("id", id)
      |> Map.put("authority", url in @server_white_list)

    cast_changeset(server, attrs)
  end

  @doc false
  def cast_changeset(server, attrs) do
    server
    |> cast(attrs, [:id, :url, :public_key, :authority])
  end

  # -----------------------------------------------------------------
  # -- Server
  # -----------------------------------------------------------------

  def get_servers(include_this_server \\ true) do
    Server
    |> include_this_server_query(include_this_server)
    |> Repo.all()
  end

  def get_authorized_server(include_this_server \\ true) do
    authorized_server_query()
    |> include_this_server_query(include_this_server)
    |> limit(1)
    |> Repo.one()
  end

  def get_authorized_servers(include_this_server \\ true) do
    authorized_server_query()
    |> include_this_server_query(include_this_server)
    |> Repo.all()
  end

  def get_not_authorized_servers(include_this_server \\ true) do
    Server
    |> where([s], s.authority == false)
    |> include_this_server_query(include_this_server)
    |> Repo.all()
  end

  defp authorized_server_query() do
    Server
    |> where([s], s.authority == true)
  end

  defp include_this_server_query(query, false) do
    with %Server{} = this_server <- get_this_server() do
      where(query, [s], s.id != ^this_server.id)
    else
      nil ->
        query
    end
  end

  defp include_this_server_query(query, true), do: query

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

        server = get_server(server_id)
        Kniffel.Cache.set(:server, server)
        server
    end
  end

  # def get_oldest_server() do
  #   case Kniffel.Cache.get(:server) do
  #     %Server{} = server ->
  #       server

  #     nil ->
  #       {:ok, private_key} = Crypto.private_key()
  #       {:ok, public_key} = ExPublicKey.public_key_from_private_key(private_key)
  #       server_id = ExPublicKey.RSAPublicKey.get_fingerprint(public_key)

  #       server = Server.get_server(server_id)
  #       Kniffel.Cache.set(:server, server)
  #       server
  #   end
  # end

  def create_server(%{"url" => url}) do
    with {:ok, %{"server" => server}} <- Kniffel.Request.get(url <> "/api/servers/this"),
         %Ecto.Changeset{} = changeset <- Server.changeset(%Server{}, server),
         {:ok, server} <- Repo.insert(changeset),
         {:ok, _reponse} <-
           Kniffel.Request.post(url <> "/api/servers", %{
             server: %{url: Server.get_this_server().url}
           }) do
      if server.authority do
        servers = get_authorized_servers(false)

        Enum.map(servers, fn server ->
          HTTPoison.post(
            server.url <> "/api/servers",
            Poison.encode!(%{server: %{url: url}}),
            [
              {"Content-Type", "application/json"}
            ]
          )
        end)

        Kniffel.Scheduler.ServerAge.get_server_age(true)
      end

      {:ok, server}
    else
      {:error, %Ecto.Changeset{}} ->
        {:error, "node " <> url <> " could not be inserted into database!"}

      {:error, _message} ->
        {:error, "node " <> url <> " could not be reached!"}
    end
  end

  def update_server(server, server_params) do
    server
    |> Server.cast_changeset(server_params)
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

      timestamp = Timex.now() |> DateTime.truncate(:second) |> Timex.format!("{ISO:Extended}")

      signature =
        Poison.encode!(%{"dices" => dices, "timestamp" => timestamp})
        |> Crypto.sign(private_key_pem)

      server = get_this_server()

      %{dices: dices, signature: signature, server_id: server.id, timestamp: timestamp}
    end
  end

  def add_this_server_to_master_server() do
    with %Server{} = this_server <- Server.get_this_server(),
         %Server{} = master_server <- Server.get_server_by_url("https://kniffel.app"),
         {:ok, %{"server" => server}} <-
           Kniffel.Request.post(master_server.url <> "/api/servers", %{
             server: %{url: this_server.url}
           }),
         {:ok, _server} <- Server.update_server(this_server, server) do
      :ok
    else
      {:ok, %{"ok" => "Server already known."}} ->
        :ok

      {:ok, %{"error" => message}} ->
        {:error, message}

      nil ->
        {:error, "could not get server from database!"}

      {:error, %Ecto.Changeset{}} ->
        {:error, "node could not be updatet in database!"}

      {:error, _message} ->
        {:error, "master-node could not be reached!"}
    end
  end
end
