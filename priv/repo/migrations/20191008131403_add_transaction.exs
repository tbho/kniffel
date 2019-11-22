defmodule Kniffel.Repo.Migrations.AddTransaction do
  use Ecto.Migration

  def change do
    create table("transaction", primary_key: false) do
      add :id, :uuid, primary_key: true
      add :timestamp, :utc_datetime, default: fragment("now()")
      add :data, :string, size: 10000
      add :signature, :string, size: 10000
    end
  end
end
