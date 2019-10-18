defmodule Kniffel.Game do
  use Ecto.Schema

  import Ecto.Query, warn: false
  import Ecto.Changeset

  alias Kniffel.{
    Repo, User, Game
  }
  alias Kniffel.Game.{
    Roll, Score
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
    IO.inspect(attrs)
    game
    |> change
    |> IO.inspect
    |> put_assoc(:users, attrs["users"] || game.users)
    |> IO.inspect
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

  def get_roll_history(id) do
    Roll
    |> Repo.get(id)
    |> Repo.preload(:predecessor)
  end

  def create_roll(roll_params \\ %{"dices" => %{a: 0, b: 0, c: 0, d: 0, e: 0}, "predecessor_id" => nil}) do
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
  end

  def create_score(game_id) do
    user =
      User
      |> Repo.all()
      |> List.first
    game = Game.get_game(game_id)
    {:ok, roll} = Game.create_roll() |> IO.inspect

    score_params =
    Map.new([{"score_type", :none}])
    |> Map.put("user", user)
    |> Map.put("game", game)
    |> Map.put("roll", roll)

    %Score{}
    |> Repo.preload([:roll, :user, :game])
    |> Score.changeset(score_params)
    |> Repo.insert()
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
    |> Repo.preload(:users)
  end

  def create_game(game_params) do
    users = Enum.map(game_params["user_ids"] || [], & User.get_user(&1))

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

end
