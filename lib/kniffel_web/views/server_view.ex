defmodule KniffelWeb.ServerView do
  use KniffelWeb, :view

  def render("index.json", %{servers: servers}) do
    %{servers: render_many(servers, KniffelWeb.ServerView, "server.json")}
  end

  def render("show.json", %{server: server}) do
    %{server: render_one(server, KniffelWeb.ServerView, "server.json")}
  end

  def render("server.json", %{server: server}) do
    %{id: server.id, url: server.url, public_key: server.public_key}
  end
end
