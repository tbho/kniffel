defmodule KniffelWeb.ShedulerController do
  use KniffelWeb, :controller

  alias Kniffel.Sheduler

  def next_round(conn, _attrs) do
    case Kniffel.Sheduler.RoundSpecification.get_next_round_specification() do
      {:error, message} ->
        json(conn, %{error: message})

      hit ->
        json(conn, %{round_response: hit})
    end
  end

  def server_age(conn, _attrs) do
    case Kniffel.Cache.get(:server_age) do
      nil ->
        json(conn, %{error: :not_found})

      hit ->
        json(conn, %{
          server_age: %{
            ages: Enum.reduce(hit.ages, %{}, &Map.put(&2, elem(&1, 0), elem(&1, 1))),
            checked_at_block: hit.checked_at_block,
            offsets: Enum.reduce(hit.offsets, %{}, &Map.put(&2, elem(&1, 0), elem(&1, 1)))
          }
        })
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
