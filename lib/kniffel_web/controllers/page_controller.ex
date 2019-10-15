defmodule KniffelWeb.PageController do
  use KniffelWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end
end
