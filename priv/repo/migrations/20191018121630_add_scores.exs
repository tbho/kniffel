defmodule Kniffel.Repo.Migrations.AddScores do
  use Ecto.Migration

  def up do
    ScoreType.create_type()

    create table("score", primary_key: false) do
      add :id, :serial, primary_key: true
      add :predecessor_id, references(:score, type: :id)
      add :dices, :map
      add :user_id, references(:user, type: :string)
      add :game_id, references(:game, type: :uuid)
      add :score_type, :score_type

      add :transaction_id, references(:transaction, type: :uuid)

      timestamps()
    end

    # create unique_index(:score, [:predecessor_id])
  end

  def down do
    drop table(:score)

    ScoreType.drop_type()
  end
end
