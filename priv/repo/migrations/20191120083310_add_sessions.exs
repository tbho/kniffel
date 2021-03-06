defmodule Kniffel.Repo.Migrations.AddSessions do
  use Ecto.Migration

  def change do
    create table(:session, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:user_id, references(:user, on_delete: :delete_all, type: :string))

      add(:access_token, :string)
      add(:access_token_issued_at, :utc_datetime)

      add(:refresh_token, :string)
      add(:refresh_token_issued_at, :utc_datetime)

      add(:ip, :string)
      add(:user_agent, :string)

      timestamps()
    end

    create(index(:session, [:user_id]))
  end
end
