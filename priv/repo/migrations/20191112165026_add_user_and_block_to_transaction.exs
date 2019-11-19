defmodule Kniffel.Repo.Migrations.AddUserAndBlockToTransaction do
  use Ecto.Migration

  def change do
    alter table("transaction") do
      add :block_id, references(:block, type: :integer, column: :index)
      add :creator, references(:user, type: :string)
    end
  end
end
