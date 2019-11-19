defmodule Kniffel.Repo.Migrations.AddGame do
  use Ecto.Migration

  def change do
    create table("game", primary_key: false) do
      add :id, :uuid, primary_key: true
      add :transaction_id, references(:transaction, type: :uuid)

      timestamps()
    end

    create table("user", primary_key: false) do
      add :id, :string, primary_key: true
      add :private_key_path, :string, size: 1000

      timestamps()
    end

    create table("game_users", primary_key: false) do
      add :user_id, references(:user, type: :string), primary_key: true

      add :game_id, references(:game, type: :uuid), primary_key: true
    end
  end
end
