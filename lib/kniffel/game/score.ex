defmodule Kniffel.Game.Score do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "score" do
    field(:dices, :map)
    field(:score_type, ScoreType, default: :none)

    belongs_to(:predecessor, Kniffel.Game.Score)
    belongs_to(:user, Kniffel.User, type: :string)
    belongs_to(:game, Kniffel.Game)

    belongs_to(:transaction, Kniffel.Blockchain.Transaction)

    timestamps()
  end

  @doc false
  def changeset(score, attrs) do
    dices =
      attrs["dices_to_roll"]
      |> Enum.map(fn x ->
        {x, :rand.uniform(6)}
      end)
      |> Map.new()

    attrs =
      attrs
      |> Map.drop(["dices"])
      |> Map.put("dices", dices)

    score
    |> cast(attrs, [:dices, :score_type])
    |> put_assoc(:predecessor, attrs["predecessor"] || score.predecessor)
    |> put_assoc(:user, attrs["user"] || score.user)
    |> put_assoc(:game, attrs["game"] || score.game)
    |> put_assoc(:transaction, attrs["transaction"] || score.transaction)

    # |> unique_constraint("predecessor")
  end

  @doc false
  def changeset_p2p(score, attrs) do
    score
    |> cast(attrs, [:id, :dices, :score_type, :predecessor_id, :user_id, :game_id])
  end

  @doc false
  def changeset_update(score, attrs) do
    score
    |> cast(attrs, [:score_type])
  end
end
