defmodule KniffelWeb.ShedulerController do
  use KniffelWeb, :controller

  alias Kniffel.User
  alias Kniffel.Sheduler

  def next_round(conn, attrs) do
    case Kniffel.Cache.get(:round_specification) do
      nil ->
        json(conn, %{error: :not_set})

      hit ->
        json(conn, %{round_response: hit})
    end
  end

  def cancel_block_propose(conn, params) do
    case Blockchain.cancel_block_propose(params) do
      {:ok, _cancel} ->
        json(conn, :ok)

      {:error, message} ->
        json(conn, %{error: message})
    end
  end

  def cancel_block_commit(conn, params) do
    case Blockchain.cancel_block_commit(params) do
      {:ok, _cancel} ->
        json(conn, :ok)

      {:error, message} ->
        json(conn, %{error: message})
    end
  end
end
