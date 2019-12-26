defmodule KniffelWeb.UserController do
  use KniffelWeb, :controller

  alias Kniffel.User

  def index(conn, attrs), do: index(get_format(conn), conn, attrs)

  def index("html", conn, _params) do
    users = User.get_users()

    render(conn, "index.html", users: users)
  end

  def index("json", conn, _params) do
    users = User.get_users()
    render(conn, "index.json", users: users)
  end

  def show(conn, attrs), do: show(get_format(conn), conn, attrs)

  def show("html", conn, %{"id" => user_id}) do
    user = User.get_user(user_id)

    render(conn, "show.html", user: user)
  end

  def show("json", conn, %{"id" => user_id}) do
    user = User.get_user(user_id)
    render(conn, "show.json", user: user)
  end

  def new(conn, _params) do
    user_changeset = User.change_user()

    render(conn, "new.html",
      changeset: user_changeset,
      action: public_user_path(conn, :create)
    )
  end

  def create(conn, attrs), do: create(get_format(conn), conn, attrs)

  def create("html", conn, %{"user" => user}) do
    case User.create_user(user) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Created!")
        |> redirect(to: public_session_path(conn, :new))

      {:error, changeset} ->
        conn
        |> put_flash(:error, "Fehler beim erstellen!")
        |> render("new.html",
          changeset: changeset,
          action: public_user_path(conn, :create)
        )
    end
  end

  def create("json", conn, %{"user" => user}) do
    case User.create_user_p2p(user) do
      {:ok, user} ->
        render(conn, "show.json", user: user)

      {:error, message} ->
        json(conn, %{error: message})
    end
  end
end
