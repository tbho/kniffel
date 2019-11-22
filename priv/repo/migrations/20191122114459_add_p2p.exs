defmodule Kniffel.Repo.Migrations.AddP2p do
  use Ecto.Migration

  def change do
    create table("server", primary_key: false) do
      add :id, :uuid, primary_key: true
      add :url, :string
      add :public_key, :string, size: 1000
    end
  end
end
