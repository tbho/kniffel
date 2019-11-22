defmodule KniffelWeb.TransactionController do
  use KniffelWeb, :controller

  alias Kniffel.Blockchain
  alias Kniffel.User

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

  def create(conn, transaction_params) do
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
end
