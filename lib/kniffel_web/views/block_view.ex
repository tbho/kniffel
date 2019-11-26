defmodule KniffelWeb.BlockView do
  use KniffelWeb, :view

  def render("index.json", %{blocks: blocks}) do
    %{blocks: render_many(blocks, KniffelWeb.BlockView, "block.json")}
  end

  def render("show.json", %{block: block}) do
    %{block: render_one(block, KniffelWeb.BlockView, "block.json")}
  end

  def render("block.json", %{block: block}) do
    Kniffel.Blockchain.Block.json(block)
  end
end
