defmodule KniffelWeb.BlockController do
  use KniffelWeb, :controller

  alias Kniffel.{Blockchain, Server, Scheduler}
  alias Kniffel.Scheduler.{RoundSpecification}
  alias Kniffel.Blockchain.Block.{Propose, ServerResponse}

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

      json(conn, %{propose_response: ServerResponse.json(propose_response)})
    else
      error_response =
        Map.new()
        |> Map.put(:error, :wrong_round_number)
        |> Map.put(:server, Server.get_this_server())
        |> ServerResponse.change()

      json(conn, %{propose_response: ServerResponse.json(error_response)})
    end
  end

  def commit(conn, %{"block" => block_params, "round_specification" => round_specification}) do
    Scheduler.cancel_timer(:cancel_block_commit)

    %{round_number: round_number} = RoundSpecification.get_round_specification()

    if round_number == round_specification["round_number"] do
      block_response = Blockchain.insert_block(block_params)
      json(conn, %{block_response: ServerResponse.json(block_response)})
    else
      error_response =
        Map.new()
        |> Map.put(:error, :wrong_round_number)
        |> Map.put(:server, Server.get_this_server())
        |> ServerResponse.change()

      json(conn, %{propose_response: ServerResponse.json(error_response)})
    end
  end

  def finalize(conn, %{
        "block_height" => height_params,
        "round_specification" => round_specification,
        "server_age" => _server_age
      }) do
    {:ok, block} = Blockchain.handle_height_change(height_params)

    # TODO: compare server_ages
    Scheduler.schedule(RoundSpecification.cast(round_specification), :next_round)
    render(conn, "show.json", block: block)
  end

  def create(conn, %{"block" => block_params}) do
    {:ok, block} = Blockchain.insert_block_from_network(block_params)
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
