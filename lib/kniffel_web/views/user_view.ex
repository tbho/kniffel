defmodule KniffelWeb.UserView do
  use KniffelWeb, :view

  def render("index.json", %{users: users}) do
    %{users: render_many(users, KniffelWeb.UserView, "user.json")}
  end

  def render("show.json", %{user: user}) do
    %{user: render_one(user, KniffelWeb.UserView, "user.json")}
  end

  def render("user.json", %{user: user}) do
    Kniffel.User.json(user)
  end
end
