defmodule Kniffel.Repo.Migrations.AddBlock do
  use Ecto.Migration

  def change do
    create table("block", primary_key: false) do
      add :index, :id, primary_key: true
      add :pre_hash, :string
      add :proof, :integer, default: 1
      add :timestamp, :utc_datetime, default: fragment("now()")
      add :transactions, {:array, :map}
      add :creator, references(:user, type: :string)
      add :hash, :string
      add :signature, :string
    end
  end
end
