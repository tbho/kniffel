defmodule Kniffel.Blockchain.Transaction do
  alias Kniffel.Blockchain.Crypto

  use Ecto.Schema
  import Ecto.Changeset

  alias Kniffel.Game
  alias Kniffel.Game.Score

  @sign_fields [:scores, :games]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "transaction" do
    belongs_to(:user, Kniffel.User)
    field :signature, :string
    field :timestamp, :utc_datetime, default: DateTime.utc_now()

    has_many(:scores, Score)
    has_many(:games, Game)
    belongs_to(:block, Kniffel.Blockchain.Block)
  end

  @doc false
  def changeset_create(transaction, %{"password" => password} = attrs) do
    transaction
    |> cast(attrs, [:signature])
    |> put_assoc(:user, attrs["user"] || transaction.scores)
    |> put_assoc(:scores, attrs["scores"] || transaction.scores)
    |> put_assoc(:games, attrs["games"] || transaction.games)
    |> put_assoc(:block, attrs["block"] || transaction.block)
    |> sign_changeset(password)
  end

  @doc false
  def changeset_p2p(transaction, attrs) do
    transaction
    |> cast(attrs, [:timestamp, :signature])
    |> put_assoc(:user, attrs["user"] || transaction.scores)
    |> put_assoc(:scores, attrs["scores"] || transaction.scores)
    |> put_assoc(:games, attrs["games"] || transaction.games)
    |> put_assoc(:block, attrs["block"] || transaction.block)
    |> verify_changeset
  end

  def sign_changeset(%Ecto.Changeset{} = changeset, password) do
    user =
      changeset
      |> fetch_field(:user_id)
      |> User.get_user
      |> User.preload_private_key(password)

    signature =
      changeset
      |> take(@sign_fields)
      |> Crypto.sign(user.private_key)

    changeset
    |> put_change(:signature, signature)
  end

  @doc "Verify a block using the public key present in it"
  def verify_changeset(%Ecto.Changeset{} = changeset) do
    signature = fetch_field(changeset, :signature)
    user =
      changeset
      |> fetch_field(:user_id)
      |> User.get_user


    case Crypto.verify(signature, user.public_key, take(changeset, @sign_fields)) do
      :ok ->
        changeset

      :invalid ->
        add_error(changeset, :hash, "invalid",
          additional: "hash is not valid for the other fields"
        )
    end
  end

  defp take(%Ecto.Changeset{} = changeset, fields) do
    Enum.map(fields, fn field ->
      {field, fetch_field(changeset, field)}
    end)
  end
end
