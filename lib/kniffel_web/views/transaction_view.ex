defmodule KniffelWeb.TransactionView do
  use KniffelWeb, :view

  def render("index.json", %{transactions: transactions}) do
    %{transactions: render_many(transactions, KniffelWeb.TransactionView, "transaction.json")}
  end

  def render("show.json", %{transaction: transaction}) do
    %{transaction: render_one(transaction, KniffelWeb.TransactionView, "transaction.json")}
  end

  def render("transaction.json", %{transaction: transaction}) do
    Kniffel.Blockchain.Transaction.json(transaction)
  end
end
