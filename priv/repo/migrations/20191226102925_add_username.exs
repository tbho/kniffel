defmodule Kniffel.Repo.Migrations.AddUsername do
  use Ecto.Migration

  def change do
    alter table("user") do
      add :user_name, :string
    end

    create unique_index("user", :user_name)
  end
end
