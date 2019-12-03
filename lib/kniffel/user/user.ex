defmodule Kniffel.User do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query, warn: false

  alias Kniffel.{
    Repo,
    User,
    Server
  }

  alias Kniffel.Blockchain.{Transaction}
  alias Kniffel.Game.{Score}

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "user" do
    field :public_key, :string
    field(:private_key, :string, virtual: true)
    field(:private_key_crypt, :string)
    field(:password, :string, virtual: true)
    field(:password_hash, :string)

    many_to_many :games, Kniffel.User, join_through: "game_users", on_replace: :delete
    has_many(:scores, Score)
    has_many(:transactions, Transaction)
    has_many(:sessions, Kniffel.User.Session)

    timestamps()
  end

  @doc false
  def changeset_gen_id(user, %{"private_key" => private_key, "password" => password} = attrs) do
    {:ok, private_key} = ExPublicKey.loads(private_key)
    {:ok, private_key_pem} = ExPublicKey.pem_encode(private_key)

    aes_256_key = :crypto.hash(:sha256, System.get_env("AES_KEY"))

    {:ok, {_pw, {init_vec, cipher_text, cipher_tag}}} =
      ExCrypto.encrypt(aes_256_key, password, private_key_pem)

    {:ok, private_key_enc} = ExCrypto.encode_payload(init_vec, cipher_text, cipher_tag)

    {:ok, public_key} = ExPublicKey.public_key_from_private_key(private_key)
    {:ok, public_key_pem} = ExPublicKey.pem_encode(public_key)

    id = ExPublicKey.RSAPublicKey.get_fingerprint(public_key)

    attrs =
      attrs
      |> Map.put("private_key_crypt", private_key_enc)
      |> Map.put("public_key", public_key_pem)
      |> Map.put("id", id)

    changeset(user, attrs)
  end

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:id, :password, :private_key_crypt, :private_key, :public_key])
    |> validate_password
    |> put_assoc(:games, attrs["games"] || user.games)
    |> put_assoc(:scores, attrs["scores"] || user.scores)
    |> put_assoc(:transactions, attrs["transactions"] || user.transactions)
  end

  @doc false
  def changeset_p2p(user, %{"public_key" => public_key} = attrs) do
    {:ok, public_key} = ExPublicKey.loads(public_key)
    id = ExPublicKey.RSAPublicKey.get_fingerprint(public_key)

    attrs =
      attrs
      |> Map.put("id", id)

    user
    |> cast(attrs, [:id, :public_key])
    |> put_assoc(:games, attrs["games"] || user.games)
    |> put_assoc(:scores, attrs["scores"] || user.scores)
    |> put_assoc(:transactions, attrs["transactions"] || user.transactions)
  end

  defp validate_password(changeset) do
    changeset
    |> validate_required([:password])
    |> validate_confirmation(:password, required: true)
    |> validate_format(:password, ~r/[A-Z]/, message: "Missing uppercase.")
    |> validate_format(:password, ~r/[a-z]/, message: "Missing lowercase.")
    |> validate_format(:password, ~r/[^a-zA-Z0-9]/, message: "Missing symbol.")
    |> validate_format(:password, ~r/[0-9]/, message: "Missing number.")
    |> validate_length(:password, min: 8)
    |> put_pass_hash()
  end

  defp put_pass_hash(%{valid?: true, changes: %{password: pw}} = changeset) do
    change(changeset, Comeonin.Argon2.add_hash(pw))
  end

  defp put_pass_hash(changeset), do: changeset

  # -----------------------------------------------------------------
  # -- User
  # -----------------------------------------------------------------

  def get_users() do
    User
    |> Repo.all()
  end

  def get_user(id) do
    User
    |> Repo.get(id)
  end

  def preload_private_key(user, password) do
    {:ok, {init_vec, cipher_text, cipher_tag}} = ExCrypto.decode_payload(user.private_key_crypt)

    private_key_pem =
      :sha256
      |> :crypto.hash(System.get_env("AES_KEY"))
      |> ExCrypto.decrypt(password, init_vec, cipher_text, cipher_tag)
      |> elem(1)

    Map.put(user, :private_key, private_key_pem)
  end

  def create_user(user_params) do
    {:ok, user} =
      %User{}
      |> Repo.preload([:games, :scores, :transactions])
      |> User.changeset_gen_id(user_params)
      |> Repo.insert()

    servers = Server.get_others_servers()

    Enum.map(servers, fn server ->
      HTTPoison.post(server.url <> "/api/users", Poison.encode!(%{user: User.json(user)}), [
        {"Content-Type", "application/json"}
      ])
    end)

    {:ok, user}
  end

  def create_user_p2p(user_params) do
    %User{}
    |> Repo.preload([:games, :scores, :transactions])
    |> User.changeset_p2p(user_params)
    |> Repo.insert()
  end

  def change_user(user \\ %User{}, user_params \\ %{}) do
    user
    |> Repo.preload([:games, :scores, :transactions])
    |> User.changeset(user_params)
  end

  @doc "Verify a block using the public key present in it"
  def json(%Kniffel.User{} = user) do
    %{
      id: user.id,
      public_key: user.public_key
    }
  end
end
