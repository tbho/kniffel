defmodule Kniffel.Repo.Migrations.AddRoll do
  use Ecto.Migration

  def change do
    create table("roll", primary_key: false) do
      add :id, :uuid, primary_key: true
      add :predecessor_id, references(:roll, type: :uuid)
      add :dices, :map

      timestamps()
    end

    create unique_index(:roll, [:predecessor_id])
  end
end
