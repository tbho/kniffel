defmodule Kniffel.Repo.Migrations.AddBlock do
  use Ecto.Migration

  def change do
    create table("block", primary_key: false) do
      add :index, :id, primary_key: true
      add :pre_hash, :string
      add :proof, :integer, default: 1
      add :timestamp, :string
      add :server_id, references(:server, type: :string)
      add :hash, :string
      add :signature, :string, size: 10000
      add :data, :string, size: 1_000_000
    end
  end
end
