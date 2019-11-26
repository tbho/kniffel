defmodule Kniffel.Server do
  use Ecto.Schema

  import Ecto.Query, warn: false
  import Ecto.Changeset

  alias Kniffel.{
    Repo,
    Server
  }

  require Logger

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "server" do
    field :url, :string
    field :public_key, :string

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
    |> cast(attrs, [:id, :url, :public_key])
  end

  # -----------------------------------------------------------------
  # -- Server
  # -----------------------------------------------------------------

  def get_servers() do
    Repo.all(Server)
  end

  def get_server(id) do
    Repo.get(Server, id)
  end

  def create_server(server_params) do
    %Server{}
    |> Server.changeset(server_params)
    |> Repo.insert()
  end

  def update_server(server, server_params) do
    server
    |> Server.changeset_update(server_params)
    |> Repo.update()
  end

  def delete_server(server) do
    Repo.delete(server)
  end

  def change_server(server \\ %Server{}, attrs \\ %{}) do
    changeset(server, attrs)
  end
end
