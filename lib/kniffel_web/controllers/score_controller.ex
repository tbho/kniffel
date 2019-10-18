defmodule KniffelWeb.ScoreController do
  use KniffelWeb, :controller

  alias Kniffel.Game

  def index(conn, _params) do
    scores = Game.get_scores()

    render(conn, "index.html", scores: scores)
  end

  def show(conn, %{"id" => score_id}) do
    score = Game.get_score(score_id)

    render(conn, "show.html", score: score)
  end

  def new(conn, %{"game_id" => game_id}) do
    score = Game.create_score(game_id) |> IO.inspect

    # render(conn, "new.html",
    #   changeset: score_changeset,
    #   action: game_score_path(conn, :create, game_id)
    # )
    conn
  end

  def update(conn, %{"game_id" => game_id, "score" => score}) do
    case Game.create_score(score) do
      {:ok, score} ->

        conn
        |> put_flash(:info, "Erstellt")
        |> redirect(to: score_path(conn, :show, score.id))

      {:error, changeset} ->

        conn
        |> put_flash(:error, "Fehler beim Erstellen")
        |> render("new.html",
          changeset: changeset,
          action: game_score_path(conn, :create, game_id)
        )
    end
  end


end
