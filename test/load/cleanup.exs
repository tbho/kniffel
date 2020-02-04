# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Kniffel.Repo.insert!(%Kniffel.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

defmodule Kniffel.Seed do
  alias Kniffel.{Game, User, Repo, Game.Score, Blockchain.Transaction, Blockchain.Block}
  import Ecto.Query, warn: false

  def cleanup_database do
    Repo.delete_all(Score)
    Repo.delete_all(from(gu in "game_users"))
    Repo.delete_all(Game)
    Repo.delete_all(Transaction)
    Repo.delete_all(User)
    Repo.delete_all(Block)
  end
end

Kniffel.Seed.cleanup_database()
