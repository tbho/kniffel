defmodule Kniffel.Repo.Migrations.AddTransaction do
  use Ecto.Migration

  def change do
    create table("transaction", primary_key: false) do
      add :id, :id, primary_key: true, autogenerate: true
      add :timestamp, :utc_datetime, default: fragment("now()")
      add :data, :string, size: 1_000_000
      add :signature, :string, size: 10000
    end
  end
end
