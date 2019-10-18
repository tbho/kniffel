defmodule Kniffel.Repo.Migrations.AddGame do
  use Ecto.Migration

  def change do
    create table("game", primary_key: false) do
      add :id, :uuid, primary_key: true

      timestamps()
    end

    create table("user", primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :string

      timestamps()
    end

    create table("game_players", primary_key: false) do
      add :user_id, references(:user, type: :uuid), primary_key: true
      add :game_id, references(:game, type: :uuid), primary_key: true
    end
  end
end
