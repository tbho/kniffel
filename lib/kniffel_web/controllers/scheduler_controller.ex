defmodule KniffelWeb.SchedulerController do
  use KniffelWeb, :controller

  alias Kniffel.Scheduler
  alias Kniffel.Scheduler.{RoundSpecification, ServerAge}

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

      server_age ->
        json(conn, %{server_age: ServerAge.json(server_age)})
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
