defmodule KniffelWeb.TransactionView do
  use KniffelWeb, :view

  def render("show.json", %{transaction: transaction}) do
    transaction
  end
end
