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
  alias Kniffel.{Game, User, Server, Blockchain, Repo}
  alias Kniffel.Blockchain.Crypto
  alias Kniffel.Blockchain.Block
  import Ecto.Query, warn: false

  def init_database do
    {:ok, private_key} = Crypto.private_key()
    {:ok, public_key} = ExPublicKey.public_key_from_private_key(private_key)
    {:ok, pem_string} = ExPublicKey.pem_encode(public_key)
    id = ExPublicKey.RSAPublicKey.get_fingerprint(public_key)

    case Server.get_server(id) do
      %Server{} = server ->
        server

      nil ->
        %Server{}
        |> Server.changeset(%{
          "url" => System.get_env("URL"),
          "public_key" => pem_string
        })
        |> Repo.insert()
    end

    url = "https://kniffel.app"

    case Server.get_server_by_url(url) do
      %Server{} = server ->
        server

      nil ->
        Server.create_server(%{"url" => url})
    end

    from(s in Server, where: s.url == "https://kniffel.app", update: [set: [authority: true]])
    |> Repo.update_all([])

    case Blockchain.get_block(0) do
      %Block{} = block ->
        block

      nil ->
        Blockchain.genesis()
    end
  end

  def create_users(count \\ 1) do
    Enum.map(0..count, fn _x ->
      user_params = %{
        "password" => "Abc123de!",
        "password_confirmation" => "Abc123de!",
        "private_key" => ""
      }

      {:ok, user} = User.create_user(user_params)
      user
    end)
  end

  def create_games(count, users) do
    Enum.map(0..count, fn _x ->
      user = Enum.random(users)

      game_params = %{
        "user_id" => user.id,
        "user_ids" => [user.id] ++ Enum.map(Enum.take_random(users -- [user], 1), & &1.id)
      }

      {:ok, game} = Game.create_game(game_params)
      game
    end)
  end

  def create_inital_score(game_id, user_id) do
    inital_score_params = %{"game_id" => game_id, "user_id" => user_id}
    Game.create_inital_score(inital_score_params)
  end

  def update_score(score) do
    score_types =
      ScoreType.__enum_map__() --
        Game.get_score_types_for_game_and_user(score.game_id, score.user_id)

    score_types = score_types -- [:none, :pre]

    Game.update_score(score, %{"score_type" => Enum.random(score_types)})
  end

  def create_score(user, game, pre_score) do
    score_params = %{
      "game_id" => game.id,
      "predecessor_id" => pre_score.id,
      "user_id" => user.id
    }

    score_params =
      ["a", "b", "c", "d", "e"]
      |> Enum.take_random(1)
      |> Enum.reduce(
        score_params,
        &Map.put(&2, "dices_to_roll_#{&1}", "on")
      )

    Game.create_score(score_params)
  end

  def create_transaction(user) do
    Blockchain.create_transaction(%{"password" => "Abc123de!"}, user)
  end

  def create_transactions(count) do
    users = create_users(Kernel.trunc(count / 5))
    games = create_games(Kernel.trunc(count / 2), users)

    Enum.map(0..count, fn _x ->
      Enum.map(Enum.take_random(games, Kernel.trunc(length(games) / 2)), fn game ->
        game = Repo.preload(game, :users)

        scores_first =
          Enum.map(game.users, fn user ->
            {:ok, score} = create_inital_score(game.id, user.id)
            score
          end)

        Enum.map(
          Enum.take_random(users, Kernel.trunc(length(scores_first) / 3)),
          &create_transaction(&1)
        )

        Blockchain.propose_new_block()
        Blockchain.create_new_block()

        scores_second = Enum.take_random(scores_first, Kernel.trunc(length(scores_first) / 2))
        scores_first = scores_first -- scores_second

        scores_second =
          scores_second
          |> Enum.map(fn score ->
            score = Repo.preload(score, :user)
            {:ok, score} = create_score(score.user, game, score)
            score
          end)

        Enum.map(
          Enum.take_random(users, Kernel.trunc(length(scores_second) / 3)),
          &create_transaction(&1)
        )

        Blockchain.propose_new_block()
        Blockchain.create_new_block()

        scores_third = Enum.take_random(scores_second, Kernel.trunc(length(scores_second) / 2))
        scores_second = scores_second -- scores_third

        scores_third =
          scores_third
          |> Enum.map(fn score ->
            score = Repo.preload(score, :user)
            {:ok, score} = create_score(score.user, game, score)
            score
          end)

        Enum.map(
          Enum.take_random(users, Kernel.trunc(length(scores_third) / 3)),
          &create_transaction(&1)
        )

        Blockchain.propose_new_block()
        Blockchain.create_new_block()

        (scores_first ++ scores_second ++ scores_third)
        |> Enum.map(&update_score(&1))

        Enum.map(users, &create_transaction(&1))

        Blockchain.propose_new_block()
        Blockchain.create_new_block()
      end)
    end)
  end
end

Kniffel.Seed.init_database()
#Kniffel.Seed.create_transactions(10)

# if System.get_env("ENV_NAME") != "production" do
#   Code.eval_file(
#     __ENV__.file
#     |> Path.dirname()
#     |> Path.join("seeds_dev.exs")
#   )
# end

# Code.eval_file(
#   __ENV__.file
#   |> Path.dirname()
#   |> Path.join("exams.exs")
# )
