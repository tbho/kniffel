defmodule KniffelWeb.TransactionController do
  use KniffelWeb, :controller

  alias Kniffel.Blockchain

  def show(conn, %{"id" => transaction_id}) do
    transaction = Blockchain.get_transaction(transaction_id)

    render(conn, "show.json", transaction: transaction)
  end
end
