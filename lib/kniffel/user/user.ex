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

  require Logger

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "user" do
    field :public_key, :string
    field(:private_key, :string, virtual: true)
    field(:private_key_crypt, :string)
    field(:password, :string, virtual: true)
    field(:password_hash, :string)
    field(:user_name, :string)

    many_to_many :games, Kniffel.User, join_through: "game_users", on_replace: :delete
    has_many(:scores, Score)
    has_many(:transactions, Transaction)
    has_many(:sessions, Kniffel.User.Session)

    timestamps()
  end

  @doc false
  defp changeset(user, %{"private_key" => ""} = attrs) do
    {:ok, private_key} = ExPublicKey.generate_key(4096)
    changeset_encrypt_private_key(user, private_key, attrs)
  end

  @doc false
  defp changeset(user, %{"private_key" => private_key} = attrs) do
    {:ok, private_key} = ExPublicKey.loads(private_key)
    changeset_encrypt_private_key(user, private_key, attrs)
  end

  @doc false
  defp changeset(user, %{"public_key" => public_key} = attrs) do
    {:ok, public_key} = ExPublicKey.loads(public_key)
    id = ExPublicKey.RSAPublicKey.get_fingerprint(public_key)

    attrs =
      attrs
      |> Map.put("id", id)

    user
    |> cast(attrs, [:id, :user_name, :public_key])
    |> put_assoc(:games, attrs["games"] || user.games)
    |> put_assoc(:scores, attrs["scores"] || user.scores)
    |> put_assoc(:transactions, attrs["transactions"] || user.transactions)
    |> unique_constraint(:user_name)
  end

  @doc false
  defp changeset(user, attrs), do: password_changeset(user, attrs)

  @doc false
  defp changeset_encrypt_private_key(user, private_key, %{"password" => password} = attrs) do
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

    password_changeset(user, attrs)
  end

  defp password_changeset(user, attrs) do
    user
    |> cast(attrs, [:id, :user_name, :password, :private_key_crypt, :private_key, :public_key])
    |> validate_password
    |> put_assoc(:games, attrs["games"] || user.games)
    |> put_assoc(:scores, attrs["scores"] || user.scores)
    |> put_assoc(:transactions, attrs["transactions"] || user.transactions)
    |> unique_constraint(:user_name)
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
    with {:ok, {init_vec, cipher_text, cipher_tag}} <-
           ExCrypto.decode_payload(user.private_key_crypt),
         aes_key <- :crypto.hash(:sha256, System.get_env("AES_KEY")),
         {:ok, private_key_pem} <-
           ExCrypto.decrypt(aes_key, password, init_vec, cipher_text, cipher_tag) do
      Map.put(user, :private_key, private_key_pem)
    else
      {:error, message} ->
        Logger.error(inspect(message))
        {:error, :could_not_load}
    end
  end

  def get_user_from_server(id, server_url) do
    with {:ok, %{"user" => user_params}} <-
           Kniffel.request().get(server_url <> "/api/users/#{id}"),
         {:ok, user} = create_user(user_params) do
      user
    else
      {:error, error} ->
        Logger.debug(inspect(error))
        error
    end
  end

  def create_user(user_params) do
    user =
      %User{}
      |> Repo.preload([:games, :scores, :transactions])
      |> changeset(user_params)
      |> Repo.insert()

    case user do
      {:ok, user} ->
        servers = Server.get_servers(false)

        Enum.map(servers, fn server ->
          Kniffel.request().post(server.url <> "/api/users", %{user: User.json(user)})
        end)

        {:ok, user}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def change_user(user \\ %User{}, user_params \\ %{}) do
    user
    |> Repo.preload([:games, :scores, :transactions])
    |> changeset(user_params)
  end

  @doc "Verify a block using the public key present in it"
  def json(%Kniffel.User{} = user) do
    %{
      id: user.id,
      user_name: user.user_name,
      public_key: user.public_key
    }
  end

  def json(user), do: nil
end
