defmodule KniffelWeb.SessionController do
  use KniffelWeb, :controller

  alias Kniffel.{User, Repo}
  alias Kniffel.User.Session

  def new(conn, _params) do
    render(conn, "new.html", %{
      action: public_session_path(conn, :create),
      register_url: ""
    })
  end

  def create(conn, %{"id" => id, "password" => password} = session) do
    format = get_format(conn)

    params = %{
      ip: conn.remote_ip |> Tuple.to_list() |> Enum.join("."),
      user_agent: List.first(get_req_header(conn, "user-agent")),
      refresh_token: session["remember_me"] == "true"
    }

    result = Session.create_session(id, password, params)

    case {format, result} do
      {"html", {:ok, session}} ->
        path = get_session(conn, :redirect_url) || "/"
        user = User.get_user(session.user_id)

        conn
        |> put_session(:access_token, session.access_token)
        |> put_flash(:info, "Logged in.")
        |> redirect(to: path)

      {"html", {:error, :not_found}} ->
        conn
        |> put_flash(:error, gettext("failure"))
        |> redirect(to: public_user_path(conn, :new))
    end
  end
end