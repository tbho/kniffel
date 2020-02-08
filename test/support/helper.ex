# defmodule Kniffel.LoadTest.Helper do
#   # use Kniffel.DataCase

#   alias Kniffel.Server

#   # import Kniffel.Factory

#   alias Kniffel.{Game, User, Repo}
#   alias Kniffel.Game.Score
#   alias Kniffel.Blockchain.{Transaction, Block}

#   import Ecto.Query, warn: false
#   import Ecto.Changeset

#   def create_game(users) do
#     user = Enum.random(users)
#     users = users -- [user]

#     game_params = %{
#       "user_id" => user.id,
#       "user_ids" => Enum.map(Enum.take_random(users -- [user], 1), & &1.id)
#     }

#     {:ok, game} = Game.create_game(game_params)
#     game
#   end

#   def create_transaction(user) do
#     Kniffel.Blockchain.create_transaction(%{"password" => "Abc123de!"}, user)
#   end

#   def create_score(user_id, game_id, pre_score_id, type, dices) do
#     score_params = %{
#       "game_id" => game_id,
#       "predecessor_id" => pre_score_id,
#       "user_id" => user_id,
#       "score_type" => type
#     }

#     score_params =
#       dices
#       |> Enum.reduce(
#         score_params,
#         &Map.put(&2, "dices_to_roll_#{&1}", "on")
#       )

#     Game.create_score(score_params)
#   end

#   def get_score_type(user_id, game_id) do
#     score_types =
#       ScoreType.__enum_map__() --
#         Game.get_score_types_for_game_and_user(game_id, user_id)

#     score_types = score_types -- [:none, :pre]

#     Enum.random(score_types)
#   end

#   def random_word() do
#     Enum.random(word_list)
#   end

#   def word_list do
#     "./wordlist.txt"
#     |> Path.expand(__DIR__)
#     |> File.read!()
#     |> String.split(~r/\n/)
#   end
# end

# #   def create_transactions(count) do
# #     users = create_users(Kernel.trunc(count / 5))
# #     games = create_games(Kernel.trunc(count / 2), users)

# #     Enum.map(0..count, fn _x ->
# #       Enum.map(Enum.take_random(games, Kernel.trunc(length(games) / 2)), fn game ->
# #         game = Repo.preload(game, :users)

# #         scores_first =
# #           Enum.map(game.users, fn user ->
# #             {:ok, score} = create_inital_score(game.id, user.id)
# #             score
# #           end)

# #         Enum.map(
# #           Enum.take_random(users, Kernel.trunc(length(scores_first) / 3)),
# #           &create_transaction(&1)
# #         )

# #         Blockchain.propose_new_block()
# #         Blockchain.commit_new_block()

# #         scores_second = Enum.take_random(scores_first, Kernel.trunc(length(scores_first) / 2))
# #         scores_first = scores_first -- scores_second

# #         scores_second =
# #           scores_second
# #           |> Enum.map(fn score ->
# #             score = Repo.preload(score, :user)
# #             {:ok, score} = create_score(score.user, game, score)
# #             score
# #           end)

# #         Enum.map(
# #           Enum.take_random(users, Kernel.trunc(length(scores_second) / 3)),
# #           &create_transaction(&1)
# #         )

# #         Blockchain.propose_new_block()
# #         Blockchain.commit_new_block()

# #         scores_third = Enum.take_random(scores_second, Kernel.trunc(length(scores_second) / 2))
# #         scores_second = scores_second -- scores_third

# #         scores_third =
# #           scores_third
# #           |> Enum.map(fn score ->
# #             score = Repo.preload(score, :user)
# #             {:ok, score} = create_score(score.user, game, score)
# #             score
# #           end)

# #         Enum.map(
# #           Enum.take_random(users, Kernel.trunc(length(scores_third) / 3)),
# #           &create_transaction(&1)
# #         )

# #         Blockchain.propose_new_block()
# #         Blockchain.commit_new_block()

# #         (scores_first ++ scores_second ++ scores_third)
# #         |> Enum.map(&update_score(&1))

# #         Enum.map(users, &create_transaction(&1))

# #         Blockchain.propose_new_block()
# #         Blockchain.commit_new_block()
# #       end)
# #     end)
# #   end
# # end
