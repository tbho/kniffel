defmodule Kniffel.Game do
  use Ecto.Schema

  import Ecto.Query, warn: false
  import Ecto.Changeset

  alias Kniffel.{
    Repo,
    User,
    Game
  }

  alias Kniffel.Game.{
    Roll,
    Score
  }

  require Logger

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "game" do
    many_to_many :users, User, join_through: "game_players", on_replace: :delete
    has_many(:scores, Score)

    timestamps()
  end

  @doc false
  def changeset(game, attrs) do
    game
    |> change
    |> put_assoc(:users, attrs["users"] || game.users)
    |> put_assoc(:scores, attrs["scores"] || game.scores)
  end

  # -----------------------------------------------------------------
  # -- Roll
  # -----------------------------------------------------------------

  def get_rolls() do
    Roll
    |> Repo.all()
  end

  def get_roll(nil), do: nil

  def get_roll(id) do
    Roll
    |> Repo.get(id)
  end

  def get_roll_with_history(nil), do: nil
  def get_roll_with_history(%Roll{predecessor: nil} = roll), do: roll

  def get_roll_with_history(%Roll{predecessor: _} = roll) do
    roll = Repo.preload(roll, :predecessor)

    Map.update!(roll, :predecessor, fn list ->
      get_roll_with_history(list)
    end)
  end

  def create_roll(roll_params \\ %{"dices" => ["a", "b", "c", "d", "e"], "predecessor_id" => nil}) do
    pre_roll = get_roll(roll_params["predecessor_id"])

    roll_params =
      roll_params
      |> Map.drop(["predecessor_id"])
      |> Map.put("predecessor", pre_roll)

    %Roll{}
    |> Repo.preload(:predecessor)
    |> Roll.changeset(roll_params)
    |> Repo.insert()
  end

  def update_roll(roll, roll_params) do
    roll
    |> Repo.preload(:predecessor)
    |> Roll.changeset(roll_params)
    |> Repo.update()
  end

  def delete_roll(roll) do
    Repo.delete(roll)
  end

  def change_roll(roll \\ %Roll{}, attrs \\ %{}) do
    roll
    |> Roll.changeset(attrs)
  end

  # -----------------------------------------------------------------
  # -- Score
  # -----------------------------------------------------------------

  def get_scores() do
    Score
    |> Repo.all()
  end

  def get_score(id) do
    Score
    |> Repo.get(id)
    |> Repo.preload([:user, :game])
  end

  def get_score_with_roll_history(id) do
    id
    |> get_score()
    |> Repo.preload([:roll])
    |> Map.update!(:roll, &get_roll_with_history(&1))
  end

  def create_score(%{"roll" => roll_params} = score_params) do
    {:ok, roll} = Game.create_roll(roll_params)

    create_score(score_params, roll)
  end

  def create_score(score_params) do
    {:ok, roll} = Game.create_roll()

    create_score(score_params, roll)
  end

  defp create_score(score_params, roll) do
    game = Game.get_game(score_params["game_id"])
    user = User.get_user(score_params["user_id"])

    score_params =
      score_params
      |> Map.drop(["game_id", "user_id"])
      |> Map.put("game", game)
      |> Map.put("user", user)
      |> Map.put("score_type", :none)
      |> Map.put("roll", roll)

    %Score{}
    |> Repo.preload([:roll, :user, :game])
    |> Score.changeset(score_params)
    |> Repo.insert()
  end

  def update_score_roll_again(score, score_params) do
    game = Game.get_game(score_params["game_id"])
    user = User.get_user(score_params["user_id"])
    {:ok, roll} = Game.create_roll(score_params["roll"])

    score_params =
      score_params
      |> Map.drop(["game_id", "user_id"])
      |> Map.put("game", game)
      |> Map.put("user", user)
      |> Map.put("roll", roll)

    update_score(score, score_params)
  end

  def update_score(score, score_params) do
    score
    |> Repo.preload([:roll, :user, :game])
    |> Score.changeset(score_params)
    |> Repo.update()
  end

  def delete_score(score) do
    Repo.delete(score)
  end

  def change_score(score \\ %Score{}, attrs \\ %{}) do
    score
    |> Repo.preload([:roll, :user, :game])
    |> Score.changeset(attrs)
  end

  # -----------------------------------------------------------------
  # -- Game
  # -----------------------------------------------------------------

  def get_games() do
    Game
    |> Repo.all()
  end

  def get_game(id) do
    Game
    |> Repo.get(id)
    |> Repo.preload([:users, scores: [:user]])
  end

  def get_game_with_roll_history(id) do
    id
    |> get_game()
    |> Map.update!(:scores, fn score ->
      Enum.map(score, &get_score_with_roll_history(&1.id))
    end)
  end

  def create_game(game_params) do
    users = Enum.map(game_params["user_ids"] || [], &User.get_user(&1))

    game_params =
      game_params
      |> Map.drop(["user_ids"])
      |> Map.put("users", users)

    %Game{}
    |> Repo.preload([:users, :scores])
    |> Game.changeset(game_params)
    |> Repo.insert()
  end

  def update_game(game, game_params) do
    game
    |> Repo.preload([:users, :scores])
    |> Game.changeset(game_params)
    |> Repo.update()
  end

  def delete_game(game) do
    Repo.delete(game)
  end

  def change_game(game \\ %Game{}, attrs \\ %{}) do
    game
    |> Repo.preload([:users, :scores])
    |> Game.changeset(attrs)
  end

  def get_score_types_for_game_and_user(game_id, user_id) do
    query = from s in Score,
          where: s.game_id == ^game_id,
          where: s.user_id == ^user_id,
          select: s.score_type
    Repo.all(query)
  end

  def is_score_without_type_for_game_and_user?(game_id, user_id) do
    game_id
    |> query_score_without_type_for_game_and_user(user_id)
    |> Repo.exists?()
  end

  def get_score_without_type_for_game_and_user(game_id, user_id) do
    game_id
    |> query_score_without_type_for_game_and_user(user_id)
    |> Repo.one()
  end

  defp query_score_without_type_for_game_and_user(game_id, user_id) do
    from s in Score,
          where: s.game_id == ^game_id,
          where: s.user_id == ^user_id,
          where: s.score_type == "none"
  end

  def is_allowed_to_roll_again?(roll) do
    is_allowed_to_roll_again?(roll, 3)
  end

  defp is_allowed_to_roll_again?(_, 0), do: false
  defp is_allowed_to_roll_again?(nil, _), do: true

  defp is_allowed_to_roll_again?(roll, limit) do
    is_allowed_to_roll_again?(roll.predecessor, limit - 1)
  end
end
