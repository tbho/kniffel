defmodule KniffelWeb.BlockController do
  use KniffelWeb, :controller

  alias Kniffel.{Blockchain, Server, Scheduler}
  alias Kniffel.Scheduler.{RoundSpecification, ServerAge}
  alias Kniffel.Blockchain.Block.{Propose, ProposeResponse}

  def index(conn, _params) do
    blocks = Blockchain.get_blocks()
    render(conn, "index.json", blocks: blocks)
  end

  def show(conn, %{"id" => block_id}) do
    block = Blockchain.get_block(block_id)
    render(conn, "show.json", block: block)
  end

  def propose(conn, %{"propose" => propose, "round_specification" => round_specification}) do
    Scheduler.cancel_timer(:cancel_block_propose)

    %{round_number: round_number} = RoundSpecification.get_round_specification()

    if round_number == round_specification["round_number"] do
      propose_response =
        propose
        |> Propose.change()
        |> Blockchain.validate_block_proposal()

      json(conn, %{propose_response: ProposeResponse.json(propose_response)})
    else
      error_response =
        Map.new()
        |> Map.put(:error, :wrong_round_number)
        |> Map.put(:server, Server.get_this_server())
        |> ProposeResponse.change()

      json(conn, %{propose_response: ProposeResponse.json(error_response)})
    end
  end

  def commit(conn, %{"block" => block_params, "round_specification" => round_specification}) do
    Scheduler.cancel_timer(:cancel_block_commit)

    %{round_number: round_number} = RoundSpecification.get_round_specification()

    if round_number == round_specification["round_number"] do
      response = Blockchain.validate_and_insert_block(block_params)
      json(conn, response)
    else
      json(conn, %{error: :wrong_round_number})
    end
  end

  def finalize(conn, %{
        "block_height" => height_params,
        "round_specification" => round_specification,
        "server_age" => server_age
      }) do
    {:ok, :accept} = Blockchain.handle_height_change(height_params)

    ServerAge.get_server_age()
    |> ServerAge.update_server_ages()

    case server_age
         |> ServerAge.cast()
         |> ServerAge.compare(ServerAge.get_server_age()) do
      true ->
        Scheduler.schedule(RoundSpecification.cast(round_specification), :next_round)
        json(conn, %{ok: :accept})

      false ->
        json(conn, %{error: "server_age wrong"})
    end

    # TODO: compare server_ages
  end

  def create(conn, %{"block" => block_params}) do
    {:ok, _block} = Blockchain.insert_block_from_network(block_params)
    json(conn, %{ok: :accept})
  end

  def height(conn, _attrs) do
    server = Server.get_this_server()
    block = Blockchain.get_last_block()
    {:ok, timestamp} = Timex.parse(block.timestamp, "{ISO:Extended}")

    json(conn, %{
      height_response: %{
        index: block.index,
        timestamp: timestamp,
        server_id: server.id,
        hash: block.hash
      }
    })
  end
end
