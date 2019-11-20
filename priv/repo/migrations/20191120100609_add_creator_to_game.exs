defmodule Kniffel.Repo.Migrations.AddCreatorToGame do
  use Ecto.Migration

  def change do
    alter table("game") do
      add :user_id, references(:user, type: :string)
    end
  end
end
