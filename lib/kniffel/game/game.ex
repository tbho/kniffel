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
    Score
  }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "game" do
    many_to_many :users, User, join_through: "game_users", on_replace: :delete
    has_many(:scores, Score)
    belongs_to(:user, Kniffel.User, type: :string)

    belongs_to(:transaction, Kniffel.Blockchain.Transaction)

    timestamps()
  end

  @doc false
  def changeset(game, attrs) do
    game
    |> cast(attrs, [])
    |> put_assoc(:user, attrs["user"] || game.user)
    |> put_assoc(:users, attrs["users"] || game.users)
    |> put_assoc(:scores, attrs["scores"] || game.scores)
    |> put_assoc(:transaction, attrs["transaction"] || game.transaction)
  end

  @doc false
  def changeset_p2p(game, attrs) do
    game
    |> cast(attrs, [:id, :inserted_at, :user_id])
    |> put_assoc(:users, attrs["users"] || game.users)
  end

  # -----------------------------------------------------------------
  # -- Score
  # -----------------------------------------------------------------
  def get_scores() do
    Repo.all(from s in Score, where: s.score_type != "none")
    |> Enum.map(&get_score_with_history(&1))
  end

  def get_scores_for_game(game_id) do
    Repo.all(from s in Score, where: s.score_type != "none", where: s.game_id == ^game_id)
    |> Enum.map(&get_score_with_history(&1))
  end

  def get_score(nil), do: nil

  def get_score(id) do
    Score
    |> Repo.get(id)
    |> Repo.preload([:user, :game])
  end

  def get_score_with_history(nil), do: nil

  def get_score_with_history(%Score{predecessor: nil} = score), do: score

  def get_score_with_history(%Score{predecessor: _} = score) do
    score = Repo.preload(score, [:predecessor, transaction: [:block]])

    Map.update!(score, :predecessor, fn pre ->
      get_score_with_history(pre)
    end)
  end

  def get_score_with_history(id) do
    id
    |> get_score
    |> get_score_with_history
  end

  def create_inital_score(score_params) do
    ["a", "b", "c", "d", "e"]
    |> Enum.reduce(
      score_params,
      &Map.put(&2, "dices_to_roll_#{&1}", "on")
    )
    |> Map.put("predecessor_id", nil)
    |> Map.put("score_type", :none)
    |> create_score
  end

  def create_score(score_params) do
    pre_score =
      with %Score{} = score <- get_score(score_params["predecessor_id"]),
           {:ok, score} <-
             update_score(score, %{"score_type" => :pre}) do
        score
      else
        nil ->
          nil

        default ->
          default
      end

    game = get_game(score_params["game_id"])
    user = User.get_user(score_params["user_id"])

    score_params =
      score_params
      |> Map.drop(["game_id", "user_id", "predecessor_id"])
      |> Map.put("game", game)
      |> Map.put("user", user)
      |> Map.put("predecessor", pre_score)

    %Score{}
    |> Repo.preload([:predecessor, :game, :user, :transaction, :server])
    |> Score.changeset(score_params)
    |> Repo.insert()
  end

  def update_score(score, score_params) do
    score
    |> Score.changeset_update(score_params)
    |> Repo.update()
  end

  def change_score(
        score \\ %Score{},
        attrs \\ Enum.reduce(
          ["a", "b", "c", "d", "e"],
          %{"predecessor_id" => nil},
          &Map.put(&2, "dices_to_roll_#{&1}", "on")
        )
      ) do
    score
    |> Repo.preload([:predecessor, :user, :game, :transaction, :server])
    |> Score.changeset(attrs)
  end

  # -----------------------------------------------------------------
  # -- Game
  # -----------------------------------------------------------------

  def get_games() do
    Game
    |> Repo.all()
  end

  def get_game(id, preload \\ []) do
    Game
    |> Repo.get(id)
    |> Repo.preload(preload)
  end

  def create_game(game_params) do
    users = Enum.map(game_params["user_ids"] || [], &User.get_user(&1))
    user = User.get_user(game_params["user_id"])

    game_params =
      game_params
      |> Map.drop(["user_ids"])
      |> Map.drop(["user_id"])
      |> Map.put("users", users)
      |> Map.put("user", user)

    %Game{}
    |> Repo.preload([:user, :users, :scores, :transaction])
    |> Game.changeset(game_params)
    |> Repo.insert()
  end

  def change_game(game \\ %Game{}, attrs \\ %{}) do
    game
    |> Repo.preload([:user, :users, :scores, :transaction])
    |> Game.changeset(attrs)
  end

  def get_score_types_for_game_and_user(game_id, user_id) do
    query =
      from s in Score,
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

  def is_allowed_to_roll_again?(score) do
    is_allowed_to_roll_again?(score, 3)
  end

  defp is_allowed_to_roll_again?(_, 0), do: false
  defp is_allowed_to_roll_again?(nil, _), do: true

  defp is_allowed_to_roll_again?(score, limit) do
    is_allowed_to_roll_again?(score.predecessor, limit - 1)
  end
end
