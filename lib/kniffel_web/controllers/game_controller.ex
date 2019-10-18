defmodule KniffelWeb.GameController do
  use KniffelWeb, :controller

  alias Kniffel.{Game, User}

  def index(conn, _params) do
    games = Game.get_games()

    render(conn, "index.html", games: games)
  end

  def show(conn, %{"id" => game_id}) do
    game = Game.get_game(game_id)

    render(conn, "show.html", game: game)
  end

  def new(conn, _params) do
    game_changeset = Game.change_game()
    users = User.get_users()

    render(conn, "new.html",
      changeset: game_changeset,
      users: users,
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
