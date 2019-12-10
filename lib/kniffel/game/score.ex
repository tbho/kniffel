defmodule Kniffel.Game.Score do
  use Ecto.Schema
  import Ecto.Changeset

  alias Kniffel.Server
  alias Kniffel.Blockchain.Crypto

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "score" do
    field(:dices, :map)
    field(:score_type, ScoreType, default: :none)
    field :signature, :string

    belongs_to(:predecessor, Kniffel.Game.Score)
    belongs_to(:user, Kniffel.User, type: :string)
    belongs_to(:game, Kniffel.Game)
    belongs_to(:server, Kniffel.Server, type: :string)
    belongs_to(:transaction, Kniffel.Blockchain.Transaction)

    timestamps()
  end

  @doc false
  def changeset(score, attrs) do
    server = Server.get_authorative_servers() |> IO.inspect

    dices_to_roll =
      Enum.reduce(["a", "b", "c", "d", "e"], [], fn capital, acc ->
        case attrs["dices_to_roll_#{capital}"] || nil do
          "on" ->
            acc ++ [capital]

          nil ->
            acc
        end
      end)

    {:ok, response} =
      HTTPoison.post(
        server.url <> "/api/servers/roll",
        Poison.encode!(%{dices_to_roll: dices_to_roll}),
        [
          {"Content-Type", "application/json"}
        ]
      )

    %{"dices" => dices, "signature" => signature, "timestamp" => timestamp} =
      Poison.decode!(response.body)

    attrs =
      attrs
      |> Map.drop(["dices"])
      |> Map.put("dices", dices)
      |> Map.put("signature", signature)
      |> Map.put("server", server)
      |> Map.put("inserted_at", timestamp)

    score
    |> cast(attrs, [:dices, :score_type, :signature, :inserted_at])
    |> put_assoc(:predecessor, attrs["predecessor"] || score.predecessor)
    |> put_assoc(:user, attrs["user"] || score.user)
    |> put_assoc(:game, attrs["game"] || score.game)
    |> put_assoc(:server, attrs["server"] || score.server)
    |> put_assoc(:transaction, attrs["transaction"] || score.transaction)

    # |> unique_constraint("predecessor")
  end

  @doc false
  def changeset_p2p(score, attrs) do
    score
    |> cast(attrs, [
      :id,
      :dices,
      :score_type,
      :predecessor_id,
      :user_id,
      :game_id,
      :inserted_at,
      :signature,
      :server_id
    ])
    |> verify_changeset
  end

  @doc "Verify a block using the public key present in it"
  def verify_changeset(%Ecto.Changeset{} = changeset) do
    with %Ecto.Changeset{} <- changeset,
         {_, signature} <- fetch_field(changeset, :signature),
         {_, server_id} <- fetch_field(changeset, :server_id),
         {_, dices} <- fetch_field(changeset, :dices),
         {_, timestamp} <- fetch_field(changeset, :inserted_at),
         %Server{} = server <- Server.get_server(server_id) do

          {:ok, timestamp} = DateTime.from_naive(timestamp, "Etc/UTC")

      case Crypto.verify(
             Poison.encode!(%{"dices" => dices, "timestamp" => DateTime.to_string(timestamp)}),
             server.public_key,
             signature
           ) do
        :ok ->
          changeset

        :invalid ->
          add_error(changeset, :signature, "invalid",
            additional: "signature is not valid for dices field"
          )
      end
    end
  end

  @doc false
  def changeset_update(score, attrs) do
    score
    |> cast(attrs, [:score_type])
  end
end
