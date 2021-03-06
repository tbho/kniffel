defmodule KniffelWeb.ScoreController do
  use KniffelWeb, :controller

  alias Kniffel.{Game, User}

  def new(conn, %{"game_id" => game_id}) do
    user =
      conn
      |> get_session(:user_id)
      |> User.get_user()

    cond do
      Game.count_score_types_for_game_and_user(game_id, user.id) >= 13 ->
        conn
        |> put_flash(:error, "Spieler hat für dieses Spiel bereits alle Würfe gemacht!")
        |> redirect(to: game_path(conn, :show, game_id))

      !Game.is_score_without_type_for_game_and_user?(game_id, user.id) ->
        {:ok, score} = Game.create_inital_score(%{"game_id" => game_id, "user_id" => user.id})

        conn
        |> redirect(to: game_score_path(conn, :re_roll, game_id, score.id))

      true ->
        score = Game.get_score_without_type_for_game_and_user(game_id, user.id)

        conn
        |> put_flash(:error, "Anderen Wurf vorher beenden")
        |> redirect(to: game_score_path(conn, :re_roll, game_id, score.id))
    end
  end

  def re_roll(conn, %{"game_id" => game_id, "id" => score_id}) do
    score = Game.get_score_with_history(score_id)

    if Game.is_allowed_to_roll_again?(score) do
      user =
        conn
        |> get_session(:user_id)
        |> User.get_user()

      score_types =
        ScoreType.__enum_map__() --
          Game.get_score_types_for_game_and_user(game_id, user.id)

      score_types = score_types -- [:none, :pre]

      render(conn, "re_roll.html", %{
        score: score,
        re_roll_action: game_score_path(conn, :re_roll_score, game_id, score.id),
        finish_action: game_score_path(conn, :finish_score, game_id, score.id),
        conn: conn,
        score_types: score_types
      })
    else
      conn
      |> put_flash(:error, "Neurollen nicht mehr erlaubt")
      |> redirect(to: game_score_path(conn, :finish, game_id, score.id))
    end
  end

  def finish(conn, %{"game_id" => game_id, "id" => score_id}) do
    score = Game.get_score_with_history(score_id)

    if score.score_type == :none do
      user =
        conn
        |> get_session(:user_id)
        |> User.get_user()

      score_types =
        ScoreType.__enum_map__() --
          Game.get_score_types_for_game_and_user(game_id, user.id)

      score_types = score_types -- [:none, :pre]

      render(conn, "finish.html", %{
        score: score,
        roll_action: game_score_path(conn, :re_roll_score, game_id, score.id),
        finish_action: game_score_path(conn, :finish_score, game_id, score.id),
        conn: conn,
        score_types: score_types
      })
    else
      conn
      |> put_flash(:error, "Wurf wurde bereits eingetragen!")
      |> redirect(to: game_path(conn, :show, game_id))
    end
  end

  def re_roll_score(conn, %{"game_id" => game_id, "id" => score_id, "score" => score_params}) do
    score = Game.get_score_with_history(score_id)

    if Game.is_allowed_to_roll_again?(score) do
      case Game.create_score(score_params) do
        {:ok, score} ->
          score = Game.get_score_with_history(score)

          if Game.is_allowed_to_roll_again?(score) do
            conn
            |> redirect(to: game_score_path(conn, :re_roll, game_id, score.id))
          else
            conn
            |> redirect(to: game_score_path(conn, :finish, game_id, score.id))
          end

        {:error, _changeset} ->
          user =
            conn
            |> get_session(:user_id)
            |> User.get_user()

          score_types =
            ScoreType.__enum_map__() --
              Game.get_score_types_for_game_and_user(game_id, user.id)

          score_types = score_types -- [:none, :pre]

          render(conn, "re_roll.html", %{
            score: score,
            re_roll_action: game_score_path(conn, :re_roll_score, game_id, score.id),
            finish_action: game_score_path(conn, :finish_score, game_id, score.id),
            conn: conn,
            score_types: score_types
          })
      end
    else
      conn
      |> put_flash(:error, "Neurollen nicht mehr erlaubt")
      |> redirect(to: game_score_path(conn, :finish, game_id, score.id))
    end
  end

  def finish_score(conn, %{"game_id" => game_id, "id" => score_id, "score" => score_params}) do
    score = Game.get_score(score_id)

    if score.score_type == :none do
      case Game.update_score(score, score_params) do
        {:ok, _} ->
          conn
          |> redirect(to: game_path(conn, :show, game_id))

        {:error, _changeset} ->
          score =
            score_id
            |> Game.get_score()
            |> Map.update!(:roll, &Game.get_score_with_history(&1))

          conn
          |> put_flash(:error, "Fehler beim Erstellen")
          |> render("update.html",
            conn: conn,
            roll_action: game_score_path(conn, :re_roll, game_id, score.id),
            update_action: game_score_path(conn, :finish, game_id, score.id)
          )
      end
    else
      conn
      |> put_flash(:error, "Wurf wurde bereits eingetragen!")
      |> redirect(to: game_path(conn, :show, game_id))
    end
  end
end
