defmodule Kniffel.Repo.Migrations.AddServer do
  use Ecto.Migration

  def change do
    create table("server", primary_key: false) do
      add :id, :string, primary_key: true
      add :url, :string
      add :public_key, :string, size: 1000

      timestamps()
    end
  end
end
