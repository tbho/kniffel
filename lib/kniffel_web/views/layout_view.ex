defmodule KniffelWeb.LayoutView do
  use KniffelWeb, :view

  alias Kniffel.Blockchain

  def data_for_transaction?(conn) do
    user_id =
      conn
      |> Plug.Conn.get_session(:user_id)

    Blockchain.data_for_transaction?(user_id)
  end
end
