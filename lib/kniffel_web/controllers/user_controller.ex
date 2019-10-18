defmodule KniffelWeb.UserController do
  use KniffelWeb, :controller

  alias Kniffel.User

  def index(conn, _params) do
    users = User.get_users()

    render(conn, "index.html", users: users)
  end

  def show(conn, %{"id" => user_id}) do
    user = User.get_user(user_id)

    render(conn, "show.html", user: user)
  end

  def new(conn, _params) do
    user_changeset = User.change_user()

    render(conn, "new.html",
      changeset: user_changeset,
      action: user_path(conn, :create)
    )
  end

  def create(conn, %{"user" => user}) do
    case User.create_user(user) do
      {:ok, user} ->

        conn
        |> put_flash(:info, "Erstellt")
        |> redirect(to: user_path(conn, :show, user.id))

      {:error, changeset} ->

        conn
        |> put_flash(:error, "Fehler beim Erstellen")
        |> render("new.html",
          changeset: changeset,
          action: user_path(conn, :create)
        )
    end
  end


end
