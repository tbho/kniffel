defmodule Kniffel.Repo.Migrations.AddScores do
  use Ecto.Migration

  def up do
    ScoreType.create_type()

    create table("score", primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, references(:user, type: :uuid)
      add :game_id, references(:game, type: :uuid)
      add :roll_id, references(:roll, type: :uuid)
      add :score_type, :score_type

      timestamps()
    end
  end

  def down do
    drop table(:score)

    ScoreType.drop_type()
  end
end
