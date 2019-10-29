defmodule Kniffel.Game.Score do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "score" do
    field(:score_type, ScoreType, default: :none)
    belongs_to(:roll, Kniffel.Game.Roll, on_replace: :nilify)
    belongs_to(:user, Kniffel.User)
    belongs_to(:game, Kniffel.Game)

    timestamps()
  end

  @doc false
  def changeset(score, attrs) do
    score
    |> cast(attrs, [:score_type])
    |> put_assoc(:roll, attrs["roll"] || score.roll)
    |> put_assoc(:user, attrs["user"] || score.user)
    |> put_assoc(:game, attrs["game"] || score.game)
  end
end
