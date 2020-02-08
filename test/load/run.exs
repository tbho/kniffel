# # Kniffel.LoadTest.cleanup_database()

# # Benchee.run(
# #   %{
# #     "create_server" => fn -> Kniffel.LoadTest.create_server() end,
# #     "create_server_key" => fn -> Kniffel.LoadTest.create_server_key() end,
# #   },
# #   time: 10,
# #   memory_time: 2
# # )

# # Kniffel.LoadTest.cleanup_database()
# # Enum.map(1..10, fn _x -> Kniffel.LoadTest.create_server(true)end)

# # Benchee.run(
# #   %{
# #     "create_user" => fn -> Kniffel.LoadTest.create_user() end,
# #   },
# #   time: 10,
# #   memory_time: 2
# # )

# # Kniffel.LoadTest.cleanup_database()
# # Enum.map(1..4, fn _x -> Kniffel.LoadTest.create_server(true)end)
# # users = Enum.map(1..10, fn _x -> Kniffel.LoadTest.create_user()end)

# # Benchee.run(
# #   %{
# #     "create_user" => fn -> Kniffel.LoadTest.create_game(users) end,
# #   },
# #   time: 10,
# #   memory_time: 2
# # )

# # ------------------------------------------------------------------------------
# # --- create_scores
# # ------------------------------------------------------------------------------

# # Kniffel.LoadTest.cleanup_database()
# # Enum.map(1..4, fn _x -> Kniffel.LoadTest.create_server(false) end)
# # users = Enum.map(1..10, fn _x -> Kniffel.LoadTest.create_user() end)
# # Benchee.run(
# #   %{
# #     "create_score" => fn game ->
# #       user = Enum.random(game.users)

# #       count = 2 - :rand.uniform(2)
# #       score = Enum.reduce(0..count, nil, fn _x, pre_score ->
# #         {:ok, score} = Kniffel.LoadTest.create_score(
# #           user.id,
# #           game.id,
# #           if pre_score do pre_score.id else nil end,
# #           :pre,
# #           if !pre_score do ["a", "b", "c", "d", "e"] else ["a", "b", "c", "d", "e"] |> Enum.take_random(:rand.uniform(5)) end
# #         )
# #         score
# #       end)

# #       Kniffel.LoadTest.create_score(
# #         user.id,
# #         game.id,
# #         score.id,
# #         Kniffel.LoadTest.get_score_type(user.id, game.id),
# #         ["a", "b", "c", "d", "e"] |> Enum.take_random(:rand.uniform(5))
# #       )
# #     end
# #   },
# #   before_each: fn input -> Kniffel.LoadTest.create_game(users) end,
# #   time: 10,
# #   memory_time: 2
# # )
# # Kniffel.LoadTest.cleanup_database()

# # ------------------------------------------------------------------------------
# # --- create_transactions
# # ------------------------------------------------------------------------------

# Kniffel.LoadTest.cleanup_database()
# Enum.map(1..4, fn _x -> Kniffel.LoadTest.create_server(false) end)
# users = Enum.map(1..10, fn _x -> Kniffel.LoadTest.create_user() end)

# Benchee.run(
#   %{
#     "create_transaction" => fn user ->
#       Kniffel.LoadTest.create_transaction(user)
#     end
#   },
#   before_each: fn input ->
#     game = Kniffel.LoadTest.create_game(users)
#     user = Enum.random(game.users)

#     count = 2 - :rand.uniform(2)

#     score =
#       Enum.reduce(0..count, nil, fn _x, pre_score ->
#         {:ok, score} =
#           Kniffel.LoadTest.create_score(
#             user.id,
#             game.id,
#             if pre_score do
#               pre_score.id
#             else
#               nil
#             end,
#             :pre,
#             if !pre_score do
#               ["a", "b", "c", "d", "e"]
#             else
#               ["a", "b", "c", "d", "e"] |> Enum.take_random(:rand.uniform(5))
#             end
#           )

#         score
#       end)

#     Kniffel.LoadTest.create_score(
#       user.id,
#       game.id,
#       score.id,
#       Kniffel.LoadTest.get_score_type(user.id, game.id),
#       ["a", "b", "c", "d", "e"] |> Enum.take_random(:rand.uniform(5))
#     )

#     user
#   end,
#   time: 10,
#   memory_time: 2
# )

# # Kniffel.LoadTest.cleanup_database()

# # Enum.map(1..4, fn _x -> Kniffel.LoadTest.create_server(false) end)
# # users = Enum.map(1..10, fn _x -> Kniffel.LoadTest.create_user() end)
# # games = Enum.map(1..10, fn _x -> Kniffel.LoadTest.create_game(users) end)
# # Benchee.run(
# #   %{
# #     "create_scores" => fn ->
# #       game = Kniffel.LoadTest.create_game(users)

# #       Enum.map(game.users, fn user ->
# #         Enum.map(1..13, fn _x ->
# #           score = Enum.reduce(1..2, nil, fn _x, pre_score ->
# #             {:ok, score} = Kniffel.LoadTest.create_score(
# #               user.id,
# #               game.id,
# #               if pre_score do pre_score.id else nil end,
# #               :pre,
# #               if !pre_score do ["a", "b", "c", "d", "e"] else ["a", "b", "c", "d", "e"] |> Enum.take_random(:rand.uniform(5)) end
# #             )
# #             score
# #           end)

# #           Kniffel.LoadTest.create_score(
# #             user.id,
# #             game.id,
# #             score.id,
# #             Kniffel.LoadTest.get_score_type(user.id, game.id),
# #             ["a", "b", "c", "d", "e"] |> Enum.take_random(:rand.uniform(5))
# #           )
# #         end)
# #       end)
# #     end
# #   },
# #   time: 10,
# #   memory_time: 2
# # )
