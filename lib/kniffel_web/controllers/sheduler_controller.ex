defmodule KniffelWeb.ShedulerController do
  use KniffelWeb, :controller

  alias Kniffel.Sheduler

  def next_round(conn, _attrs) do
    case Kniffel.Sheduler.get_next_round_specification() do
      {:error, message} ->
        json(conn, %{error: message})

      hit ->
        json(conn, %{round_response: hit})
    end
  end

  def cancel_block_propose(conn, %{"cancel_block_propose" => params}) do
    case Sheduler.handle_cancel_block_propose(params) do
      :ok ->
        json(conn, :ok)

      {:error, message} ->
        json(conn, %{error: message})
    end
  end

  def cancel_block_commit(conn, %{"cancel_block_commit" => params}) do
    case Sheduler.handle_cancel_block_commit(params) do
      :ok ->
        json(conn, :ok)

      {:error, message} ->
        json(conn, %{error: message})
    end
  end
end
