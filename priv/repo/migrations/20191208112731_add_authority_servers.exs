defmodule Kniffel.Repo.Migrations.AddAuthorityServers do
  use Ecto.Migration

  def change do
    alter table("server") do
      add :authority, :boolean
    end
  end
end
