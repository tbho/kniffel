defmodule Kniffel.Repo.Migrations.AddPrivateKeyToUser do
  use Ecto.Migration

  def change do
    alter table("user") do
      add :private_key_crypt, :string, size: 10000
      add :password_hash, :string
    end
  end
end
