defmodule Kniffel.Repo.Migrations.AddUserAndBlockToTransaction do
  use Ecto.Migration

  def change do
    alter table("transaction") do
      add :block_index, references(:block, type: :integer, column: :index)
      add :user_id, references(:user, type: :string)
    end
  end
end
