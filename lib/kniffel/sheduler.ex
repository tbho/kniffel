defmodule Kniffel.Sheduler do
  # use Quantum.Scheduler,
  #   otp_app: :kniffel

  @default_round_length 30

  use GenServer
  alias Kniffel.{Server, Blockchain.Crypto}
  alias DateTime
  require Logger

  def start_link(state) do
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  def init(state) do
    # TODO: compare blocks with other servers (get server adress without adding server to network)
    # TODO: add server to network
    %{round_begin: round_begin} = get_round_time()

    Process.send_after(
      self(),
      :new_round,
      Timex.diff(round_begin, Timex.now(), :milliseconds)
    )

    {:ok, state}
  end

  def handle_info(:new_round, state) do
    Logger.info("--- Start a new round --------------------------------------------------")
    %{round_length: round_length} = get_round_time()
    # do nothing if no other server in network
    servers = Server.get_authorized_servers(false)

    if length(servers) > 0 do
      # TODO: after n rounds calculate new round times
      server = Kniffel.Server.get_this_server()

      case Kniffel.Blockchain.is_leader?(server) do
        true ->
          Process.send(self(), :propose_block, [])
          schedule_block_commit(Kernel.trunc(round_length / 3))
          schedule_block_finalization(Kernel.trunc(round_length / 3) * 2)

        false ->
          posittion = Kniffel.Blockchain.get_position_in_server_queue(server)
          schedule_cancel_block_propose(Kernel.trunc(round_length / 3))
          schedule_cancel_block_commit(Kernel.trunc(round_length / 3) * 2)
      end
    end

    # shedule the new round
    schedule_round_begin(round_length)
    {:noreply, state}
  end

  def handle_info(:propose_block, state) do
    case Kniffel.Blockchain.propose_new_block() do
      {:ok, _propose} ->
        :ok

      {:error, :no_transactions} ->
        cancel_block_propose(:no_transaction)
    end

    {:noreply, state}
  end

  def handle_info(:commit_block, state) do
    case Kniffel.Blockchain.commit_new_block() do
      {:ok, _block} ->
        :ok

      {:error, :no_propose_for_block} ->
        cancel_block_commit(:not_valid)
    end

    {:noreply, state}
  end

  def handle_info(:finalize_block, state) do
    Kniffel.Blockchain.finalize_block()
    {:noreply, state}
  end

  def handle_info(:cancel_block_propose, state) do
    cancel_block_propose(:timeout)
    {:noreply, state}
  end

  def handle_info(:cancel_block_commit, state) do
    cancel_block_commit(:timeout)
    {:noreply, state}
  end

  # ----------------------------------------------------------------------------
  # ---  Shedule - Methods ---
  # ----------------------------------------------------------------------------

  def schedule_block_proposal(seconds) do
    timer = Process.send_after(self(), :propose_block, seconds * 1000)
    Kniffel.Cache.set(:propose_block_timer, timer, ttl: seconds)
    timer
  end

  def schedule_block_commit(seconds) do
    timer = Process.send_after(self(), :create_block, seconds * 1000)
    Kniffel.Cache.set(:create_block_timer, timer, ttl: seconds)
    timer
  end

  def schedule_block_finalization(seconds) do
    timer = Process.send_after(self(), :finalize_block, seconds * 1000)
    Kniffel.Cache.set(:finalize_block_timer, timer, ttl: seconds)
    timer
  end

  def schedule_round_begin(seconds) do
    timer = Process.send_after(self(), :new_round, seconds * 1000)
    Kniffel.Cache.set(:new_round_timer, timer, ttl: seconds)
    timer
  end

  def schedule_cancel_block_propose(seconds) do
    timer = Process.send_after(self(), :cancel_block_propose, seconds * 1000)
    Kniffel.Cache.set(:cancel_block_propose_timer, timer, ttl: seconds)
    timer
  end

  def schedule_cancel_block_commit(seconds) do
    timer = Process.send_after(self(), :cancel_block_commit, seconds * 1000)
    Kniffel.Cache.set(:cancel_block_commit_timer, timer, ttl: seconds)
    timer
  end

  # ----------------------------------------------------------------------------
  # ---  Helper - Methods ---
  # ----------------------------------------------------------------------------

  def cancel_timer(name) do
    Kniffel.Cache.take(name)
    |> Process.cancel_timer()
  end

  def read_timer(name) do
    Kniffel.Cache.get(name)
    |> Process.read_timer()
  end

  defp get_round_time() do
    case Kniffel.Cache.get(:round_specification) do
      nil ->
        request_round_specification_from_network()

      hit ->
        hit
    end
  end

  defp request_round_specification_from_network() do
    servers = Server.get_authorized_servers(false)

    default_round_specification = %{
      round_length: @default_round_length,
      round_begin: Timex.add(Timex.now(), Timex.Duration.from_seconds(2)),
      round_number: 1
    }

    {round_specification, _bool} =
      Enum.reduce(servers, {default_round_specification, false}, fn
        server, {round_specification, true} ->
          {round_specification, true}

        server, {default, false} ->
          {:ok, response} = HTTPoison.get(server.url <> "/api/sheduler/next_round")

          with %{"round_response" => round_response} <- Poison.decode!(response.body) do
            round_specification = %{
              round_length: round_response["round_time"],
              round_begin: round_response["round_begin"],
              round_number: round_response["round_number"]
            }

            {round_specification, true}
          else
            %{"error" => error} ->
              {default, false}
          end
      end)

    Kniffel.Cache.set(:round_specification, round_specification)
    round_specification
  end

  # ----------------------------------------------------------------------------
  # ---  Helper - Methods ---
  # ----------------------------------------------------------------------------

  def cancel_block_propose(reason) do
    round_number = Kniffel.Cache.get(:round_number)
    this_server = Server.get_this_server()

    data = %{
      server_id: this_server.id,
      round_number: round_number,
      reason: reason
    }

    with {:ok, private_key} <- Crypto.private_key(),
         {:ok, private_key_pem} <- ExPublicKey.pem_encode(private_key) do
      signature =
        data
        |> Poison.encode!()
        |> Crypto.sign(private_key_pem)

      Server.get_authorized_servers(false)
      |> Enum.map(fn server ->
        {:ok, response} =
          HTTPoison.post(
            server.url <> "/api/blocks/cancel_propose",
            Poison.encode!(%{cancel_block_propose: Map.put(data, :signature, signature)}),
            [
              {"Content-Type", "application/json"}
            ]
          )

        with %{"cancel_block_propose_response" => cancel_block_propose_response} <-
               Poison.decode!(response.body) do
          :ok = cancel_block_propose_response
        end
      end)
    end
  end

  def cancel_block_commit(reason) do
    round_number = Kniffel.Cache.get(:round_number)
    this_server = Server.get_this_server()

    data = %{
      server_id: this_server.id,
      round_number: round_number,
      reason: reason
    }

    with {:ok, private_key} <- Crypto.private_key(),
         {:ok, private_key_pem} <- ExPublicKey.pem_encode(private_key) do
      signature =
        data
        |> Poison.encode!()
        |> Crypto.sign(private_key_pem)

      Server.get_authorized_servers(false)
      |> Enum.map(fn server ->
        {:ok, response} =
          HTTPoison.post(
            server.url <> "/api/blocks/cancel_commit",
            Poison.encode!(%{cancel_block_propose: Map.put(data, :signature, signature)}),
            [
              {"Content-Type", "application/json"}
            ]
          )

        with %{"cancel_block_propose_response" => cancel_block_propose_response} <-
               Poison.decode!(response.body) do
          :ok = cancel_block_propose_response
        end
      end)
    end
  end

  def handle_cancel_block_propose(%{
        "server_id" => server_id,
        "round_number" => round_number,
        "reason" => reason
      }) do
    with %Server{authority: true} <- Server.get_server(server_id) do
      case reason do
        :no_transaction ->
          :ok

        # cancel timers and wait for next round
        # validate there a no transactions with timestamp before propose_start

        :timeout ->
          # get_round_times(round_number)
          :ok

        # compare DateTime.now() to round_times

        :not_valid ->
          :ok
          # cancel timers and wait for next round
      end
    else
      nil ->
        {:unknown_server, server_id}
    end
  end

  def handle_cancel_block_commit(%{
        "server_id" => server_id,
        "round_number" => round_number,
        "reason" => reason
      }) do
    with %Server{authority: true} <- Server.get_server(server_id) do
      case reason do
        :timeout ->
          :ok

        # get_round_times(round_number)

        # compare DateTime.now() to round_times

        :not_valid ->
          :ok
          # cancel timers and wait for next round
      end
    else
      nil ->
        {:unknown_server, server_id}
    end
  end
end
