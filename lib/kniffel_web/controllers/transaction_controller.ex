defmodule KniffelWeb.TransactionController do
  use KniffelWeb, :controller

  alias Kniffel.Blockchain
  alias Kniffel.User

  def index(conn, %{"filter" => filter_params}), do: filter_transactions(conn, filter_params)
  def index(conn, _params), do: filter_transactions(conn, %{})

  defp filter_transactions(conn, filter_params) do
    transactions = Blockchain.get_transactions(filter_params)
    render(conn, "index.json", transactions: transactions)
  end

  def show(conn, %{"id" => transaction_id}) do
    transaction = Blockchain.get_transaction(transaction_id)
    render(conn, "show.json", transaction: transaction)
  end

  def new(conn, _params) do
    user =
      conn
      |> get_session(:user_id)
      |> User.get_user()

    render(conn, "new.html", %{
      user: user,
      action: transaction_path(conn, :create)
    })
  end

  def create(conn, attrs), do: create(get_format(conn), conn, attrs)

  def create("html", conn, transaction_params) do
    user =
      conn
      |> get_session(:user_id)
      |> User.get_user()

    case Blockchain.create_transaction(transaction_params, user) do
      {:ok, _transaction} ->
        conn
        |> put_flash(:info, "Transaction created successful.")
        |> redirect(to: game_path(conn, :index))

      {:error, message} ->
        conn
        |> put_flash(:error, message)
        |> redirect(to: game_path(conn, :index))
    end
  end

  def create("json", conn, %{"transaction" => transaction_params, "server" => %{"url" => url}}) do
    case Blockchain.insert_transaction(transaction_params, url) do
      {:ok, transaction} ->
        render(conn, "show.json", transaction: transaction)

      {:error, message} ->
        json(conn, %{error: message})
    end
  end
end
