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
    |> cast(attrs, [:id, :data, :timestamp, :signature])
    |> put_assoc(:user, attrs["user"] || transaction.user)
    |> cast_assoc(:scores, with: &Score.changeset_p2p/2)
    |> cast_assoc(:games, with: &Game.changeset_p2p/2)
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
         {_, user} <- fetch_field(changeset, :user),
         %User{} = user <- User.get_user(user.id) do
      data =
        changeset
        |> take(@sign_fields)
        |> Poison.encode!()

      case Crypto.verify(data, user.public_key, signature) do
        :ok ->
          changeset

        :invalid ->
          add_error(changeset, :signature, "invalid",
            additional: "signature is not valid for the other fields"
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

  @doc "Verify a block using the public key present in it"
  def json(%Kniffel.Blockchain.Transaction{} = transaction) do
    %{
      id: transaction.id,
      data: Poison.decode!(transaction.data),
      signature: transaction.signature,
      timestamp: transaction.timestamp,
      user_id: transaction.user_id,
      block_index: transaction.block_index
    }
  end
end
