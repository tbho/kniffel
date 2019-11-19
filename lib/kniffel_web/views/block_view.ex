defmodule KniffelWeb.BlockView do
  use KniffelWeb, :view

  def render("show.json", %{block: block}) do
    block
  end
end
