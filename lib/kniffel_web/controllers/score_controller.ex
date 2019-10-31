defmodule KniffelWeb.ScoreController do
  use KniffelWeb, :controller

  alias Kniffel.{Game, User}

  def show(conn, %{"game_id" => game_id, "id" => score_id}) do
    score = Game.get_score_with_roll_history(score_id)

    if Game.is_allowed_to_roll_again?(score.roll) do
      user = List.first(User.get_users())
      score_types = ScoreType.__enum_map__() -- Game.get_score_types_for_game_and_user(game_id, user.id)
      score_types = score_types -- [:none]

      render(conn, "show.html", %{
        score: score,
        roll_action: game_score_path(conn, :re_roll, game_id, score.id),
        update_action: game_score_path(conn, :update, game_id, score.id),
        changeset: Game.change_score(),
        score_types: score_types
      })
    else
      conn
      |> put_flash(:error, "Neurollen nicht mehr erlaubt")
      |> redirect(to: game_score_path(conn, :edit, game_id, score.id))
    end
  end

  def new(conn, %{"game_id" => game_id}) do
    user = List.first(User.get_users())

    if ! Game.is_score_without_type_for_game_and_user?(game_id, user.id) do
      {:ok, score} = Game.create_score(%{"game_id" => game_id, "user_id" => user.id})

      conn
      |> redirect(to: game_score_path(conn, :show, game_id, score.id))
    else
      score = Game.get_score_without_type_for_game_and_user(game_id, user.id)

      conn
      |> put_flash(:error, "Anderen Wurf vorher beenden")
      |> redirect(to: game_score_path(conn, :show, game_id, score.id))
    end
  end

  def edit(conn, %{"game_id" => game_id, "id" => score_id}) do
    score = Game.get_score_with_roll_history(score_id)

    if score.score_type == :none do
      user = List.first(User.get_users())
      score_types = ScoreType.__enum_map__() -- Game.get_score_types_for_game_and_user(game_id, user.id)
      score_types = score_types -- [:none]

      render(conn, "update.html", %{
        score: score,
        roll_action: game_score_path(conn, :re_roll, game_id, score.id),
        update_action: game_score_path(conn, :update, game_id, score.id),
        changeset: Game.change_score(),
        score_types: score_types
      })
    else
      conn
      |> put_flash(:error, "Wurf wurde bereits eingetragen!")
      |> redirect(to: game_path(conn, :show, game_id))
    end
  end

  def re_roll(conn, %{"game_id" => game_id, "id" => score_id, "score" => score_params}) do
    score = Game.get_score_with_roll_history(score_id)

    if Game.is_allowed_to_roll_again?(score.roll) do
      case Game.update_score_roll_again(score, score_params) do
        {:ok, score} ->
          conn
          |> redirect(to: game_score_path(conn, :show, game_id, score.id))

        {:error, changeset} ->
          score =
            score_id
            |> Game.get_score()
            |> Map.update!(:roll, &Game.get_roll_with_history(&1))

          conn
          |> put_flash(:error, "Fehler beim Erstellen")
          |> render("show.html",
            changeset: changeset,
            roll_action: game_score_path(conn, :re_roll, game_id, score.id),
            update_action: game_score_path(conn, :update, game_id, score.id)
          )
      end
    else
      conn
      |> put_flash(:error, "Neurollen nicht mehr erlaubt")
      |> redirect(to: game_score_path(conn, :update, game_id, score.id))
    end
  end

  def update(conn, %{"game_id" => game_id, "id" => score_id, "score" => score_params}) do
    score = Game.get_score(score_id)

    if score.score_type == :none do
      case Game.update_score(score, score_params) do
        {:ok, _} ->
          conn
          |> redirect(to: game_path(conn, :show, game_id))

        {:error, changeset} ->
          score =
            score_id
            |> Game.get_score()
            |> Map.update!(:roll, &Game.get_roll_with_history(&1))

          conn
          |> put_flash(:error, "Fehler beim Erstellen")
          |> render("update.html",
            changeset: changeset,
            roll_action: game_score_path(conn, :re_roll, game_id, score.id),
            update_action: game_score_path(conn, :update, game_id, score.id)
          )
      end
    else
      conn
      |> put_flash(:error, "Wurf wurde bereits eingetragen!")
      |> redirect(to: game_path(conn, :show, game_id))
    end
  end
end
