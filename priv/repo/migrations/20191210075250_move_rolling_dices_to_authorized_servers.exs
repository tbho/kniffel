defmodule Kniffel.Repo.Migrations.MoveRollingDicesToAuthorizedServers do
  use Ecto.Migration

  def change do
    alter table("score") do
      add :signature, :string, size: 10000
      add :server_id, references(:server, type: :string)
    end
  end
end
