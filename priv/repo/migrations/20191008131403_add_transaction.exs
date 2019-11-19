defmodule Kniffel.Repo.Migrations.AddTransaction do
  use Ecto.Migration

  def change do
    create table("transaction", primary_key: false) do
      add :id, :uuid, primary_key: true
      add :timestamp, :utc_datetime, default: fragment("now()")
      add :games, {:array, :map}
      add :scores, {:array, :map}
      add :signature, :string
    end
  end
end
