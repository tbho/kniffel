defmodule KniffelWeb.SchedulerController do
  use KniffelWeb, :controller

  alias Kniffel.Scheduler
  alias Kniffel.Scheduler.RoundSpecification

  def next_round(conn, _attrs) do
    case Kniffel.Scheduler.RoundSpecification.get_next_round_specification() do
      {:error, message} ->
        json(conn, %{error: message})

      hit ->
        json(conn, %{round_response: RoundSpecification.json(hit)})
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

  def cancel_block_propose(conn, %{
        "cancel_block_propose" => params,
        "round_specification" => round_specification_params
      }) do
    round_specification = RoundSpecification.cast(round_specification_params)

    case Scheduler.handle_cancel_block_propose(params, round_specification) do
      :ok ->
        json(conn, %{cancel_block_propose_response: :ok})

      {:error, message} ->
        json(conn, %{error: message})
    end
  end

  def cancel_block_commit(conn, %{
        "cancel_block_commit" => params,
        "round_specification" => round_specification_params
      }) do
    round_specification = RoundSpecification.cast(round_specification_params)

    case Scheduler.handle_cancel_block_commit(params, round_specification) do
      :ok ->
        json(conn, %{cancel_block_commit_response: :ok})

      {:error, message} ->
        json(conn, %{error: message})
    end
  end
end
