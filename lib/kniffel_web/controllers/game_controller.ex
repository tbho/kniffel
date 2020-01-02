defmodule KniffelWeb.GameController do
  use KniffelWeb, :controller

  alias Kniffel.{Game, User, Game.Score}

  def index(conn, _params) do
    user_id = get_session(conn, :user_id)
    games = Game.get_games_for_user(user_id)

    render(conn, "index.html", games: games)
  end

  def show(conn, %{"id" => game_id}) do
    game = Game.get_game(game_id, [:users])
    scores = Game.get_scores_for_game(game_id)
    scores = Score.calculate_scores(scores, game.users)

    render(conn, "show.html", game: game, scores: scores)
  end

  def new(conn, _params) do
    game_changeset = Game.change_game()
    users = User.get_users()
    user_id = get_session(conn, :user_id)

    render(conn, "new.html",
      changeset: game_changeset,
      users: users,
      user_id: user_id,
      action: game_path(conn, :create)
    )
  end

  def create(conn, %{"game" => game}) do
    case Game.create_game(game) do
      {:ok, game} ->
        conn
        |> put_flash(:info, "Erstellt")
        |> redirect(to: game_path(conn, :show, game.id))

      {:error, changeset} ->
        users = User.get_users()

        conn
        |> put_flash(:error, "Fehler beim Erstellen")
        |> render("new.html",
          changeset: changeset,
          users: users,
          action: game_path(conn, :create)
        )
    end
  end
end
