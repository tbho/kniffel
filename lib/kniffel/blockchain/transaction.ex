defmodule Kniffel.Blockchain.Transaction do
  alias Kniffel.Blockchain.Crypto

  use Ecto.Schema
  import Ecto.Changeset

  alias Kniffel.Game
  alias Kniffel.Game.Score
  alias Kniffel.User

  @sign_fields [:data, :timestamp]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "transaction" do
    field :signature, :string
    field :data, :string
    field :timestamp, :utc_datetime, default: DateTime.truncate(DateTime.utc_now(), :second)

    has_many(:scores, Score)
    has_many(:games, Game)

    belongs_to(:block, Kniffel.Blockchain.Block,
      type: :id,
      foreign_key: :block_index,
      references: :index
    )

    belongs_to(:user, Kniffel.User, type: :string)
  end

  @doc false
  def changeset_create(transaction, %{"password" => password} = attrs) do
    transaction
    |> cast(attrs, [:data])
    |> put_assoc(:user, attrs["user"] || transaction.user)
    |> put_assoc(:block, attrs["block"] || transaction.block)
    |> put_assoc(:scores, attrs["scores"] || transaction.scores)
    |> put_assoc(:games, attrs["games"] || transaction.games)
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

  def sign_changeset(changeset, password) do
    with %Ecto.Changeset{} <- changeset,
         {_, user} <- fetch_field(changeset, :user),
         %User{} = user <- User.preload_private_key(user, password) do
      signature =
        changeset
        |> take(@sign_fields)
        |> IO.inspect()
        |> Poison.encode!()
        |> Crypto.sign(user.private_key)

      changeset
      |> put_change(:signature, signature)
    end
  end

  @doc "Verify a block using the public key present in it"
  def verify_changeset(%Ecto.Changeset{} = changeset) do
    with %Ecto.Changeset{} <- changeset,
         {_, signature} <- fetch_field(changeset, :signature),
         {_, data} <- fetch_field(changeset, :data),
         {_, user_id} <- fetch_field(changeset, :user_id),
         %User{} = user <- User.get_user(user_id) do
      case Crypto.verify(signature, user.public_key, data) do
        :ok ->
          changeset

        :invalid ->
          add_error(changeset, :hash, "invalid",
            additional: "hash is not valid for the other fields"
          )
      end
    end
  end

  defp take(%Ecto.Changeset{} = changeset, fields) do
    Enum.reduce(fields, %{}, fn field, map ->
      case fetch_field(changeset, field) do
        {_, data} ->
          Map.put(map, field, data)
      end
    end)
  end
end
