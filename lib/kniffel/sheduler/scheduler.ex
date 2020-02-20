defmodule Kniffel.Scheduler do
  use GenServer
  alias Kniffel.{Server, Blockchain}
  alias Kniffel.Blockchain.Crypto
  alias Kniffel.Scheduler.{RoundSpecification, ServerAge}
  require Logger

  @http_client Application.get_env(:kniffel, :request)
  @crypto Application.get_env(:kniffel, :crypto)

  def start_link(state) do
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  def init(state) do
    Process.send(Kniffel.Scheduler, :prepare_node, [])
    {:ok, state}
  end

  def handle_info(event, state) do
    spawn(Kniffel.Scheduler, :handle_event, [event])
    {:noreply, state}
  end

  def handle_event(:prepare_node) do
    Logger.info("-# Prepare and start scheduler")

    with {:master, :ok} <- {:master, Server.add_this_server_to_master_server()},
         # add server to network
         {:height, :ok} <- {:height, Blockchain.compare_block_height_with_network()},
         # compare blocks with other servers (get server adress without adding server to network)
         {:transaction, :ok} <-
           {:transaction, Blockchain.request_not_confirmed_transactions_from_network()},
         # get not confirmed transactions from master network and maybe insert into database
         {:round_specification, r} when r in [:ok, :default] <-
           {:round_specification, RoundSpecification.request_round_specification_from_network()},
         # get the round_specification for next round from master_nodes
         {:server_age, a} when a in [:ok, :default] <-
           {:server_age, ServerAge.request_server_age_from_network()},
         # get server_age from network
         %{} = round_specification <- RoundSpecification.get_next_round_specification() do
      # calculate diff (in milliseconds) till start of new round
      Logger.debug("Starting with: #{inspect(round_specification)}")

      diff_milliseconds =
        round_specification
        |> RoundSpecification.get_round_time(:round_begin)
        |> RoundSpecification.calculate_diff_to_now()

      # shedule new round
      Process.send_after(Kniffel.Scheduler, :next_round, diff_milliseconds)

      Logger.info(
        "-✓ Started scheduler successful! First round will start at: " <>
          Timex.format!(
            RoundSpecification.get_round_time(round_specification, :round_begin),
            "{ISO:Extended}"
          )
      )
    else
      {:master, {:error, message}} ->
        Logger.debug(inspect(message))

        Logger.error(
          "Error while preparing to start scheduler (add server to master_server network), repeating in 10 seconds again!"
        )

        Process.send_after(Kniffel.Scheduler, :prepare_node, 10_000)

      {reason, :error} ->
        Logger.error(
          "Error while preparing to start scheduler (request #{inspect(reason)} data from network), repeating in 10 seconds again!"
        )

        Process.send_after(Kniffel.Scheduler, :prepare_node, 10_000)

      {:error, :no_round_specification_in_cache} ->
        Logger.error(
          "Error while preparing to start scheduler (no round_specification in cache), repeating in 10 seconds again!"
        )

        Process.send_after(Kniffel.Scheduler, :prepare_node, 10_000)
    end
  end

  def handle_event(:next_round) do
    Logger.info("-> Start a new round")
    RoundSpecification.start_new_round()
    round_specification = RoundSpecification.get_round_specification()
    # get other master nodes
    servers = Server.get_authorized_servers(false)

    # do nothing if no other server in network
    if length(servers) > 0 do
      server = Kniffel.Server.get_this_server()

      # if this server is oldest he is choosen for block creation
      # if not he is choosen to abort if lead server runs in a timeout

      case ServerAge.is_leader?(server.id) do
        true ->
          Logger.debug(
            "--- Server is leader. Round number: #{inspect(round_specification.round_number)}"
          )

          schedule(round_specification, :propose_block)
          schedule(round_specification, :commit_block)
          schedule(round_specification, :finalize_block)

        false ->
          # position = Kniffel.Blockchain.get_position_in_server_queue(server)
          Logger.debug(
            "--- Server is canceler. Round number: #{inspect(round_specification.round_number)}"
          )

          schedule(round_specification, :cancel_block_propose)
          schedule(round_specification, :cancel_block_commit)
      end
    else
      Logger.info("--- No other master node found! I will shedule a new round and try again.")
      # if no other server in network save new round specification

      # schedule the new round
      next_round_specification = RoundSpecification.get_next_round_specification()
      schedule(next_round_specification, :next_round)

      Logger.info(
        "-! Round finished. Next Round will start at: " <>
          Timex.format!(next_round_specification.round_begin, "{ISO:Extended}")
      )
    end
  end

  def handle_event(:propose_block) do
    Logger.info("--- Propose a new block")

    case Kniffel.Blockchain.propose_new_block() do
      {:ok, _propose} ->
        :ok

      {:error, :no_transactions} ->
        cancel_block_propose(:no_transaction)
    end
  end

  def handle_event(:commit_block) do
    Logger.info("--- Commit a new block")

    case Kniffel.Blockchain.commit_new_block() do
      {:ok, _block} ->
        :ok

      {:error, :no_propose_for_block} ->
        cancel_block_commit(:not_valid)
    end
  end

  def handle_event(:finalize_block) do
    Logger.info("--- Finalize new block")

    case Kniffel.Blockchain.finalize_block() do
      :ok ->
        next_round_specification = RoundSpecification.get_next_round_specification()
        schedule(next_round_specification, :next_round)

      {:error, error} ->
        Logger.debug(error)
    end
  end

  def handle_event(:cancel_block_propose) do
    Logger.info("--- Cancel block propose (timeout)")
    cancel_block_propose(:timeout)
  end

  def handle_event(:cancel_block_commit) do
    Logger.info("--- Cancel block commit (timeout)")
    cancel_block_commit(:timeout)
  end

  # ----------------------------------------------------------------------------
  # ---  Shedule - Methods ---
  # ----------------------------------------------------------------------------
  def schedule(round_specification, type) do
    cache_atom = (Atom.to_string(type) <> "_timer") |> String.to_atom()
    time = RoundSpecification.get_round_time(round_specification, type)

    case read_timer(type) do
      false ->
        timer =
          Process.send_after(
            Kniffel.Scheduler,
            type,
            RoundSpecification.calculate_diff_to_now(time)
          )

        Kniffel.Cache.set(cache_atom, timer,
          ttl: RoundSpecification.calculate_diff_to_now(time, :seconds)
        )

        :ok

      time when is_integer(time) ->
        Logger.debug("Timer " <> inspect(type) <> " still runnning!")
    end
  end

  # ----------------------------------------------------------------------------
  # ---  Helper - Methods ---
  # ----------------------------------------------------------------------------

  def cancel_timer(name) do
    cache_atom = (Atom.to_string(name) <> "_timer") |> String.to_atom()

    case Kniffel.Cache.take(cache_atom) do
      nil ->
        :ok

      process ->
        Process.cancel_timer(process)
    end
  end

  def read_timer(name) do
    cache_atom = (Atom.to_string(name) <> "_timer") |> String.to_atom()

    case Kniffel.Cache.get(cache_atom) do
      nil ->
        false

      process ->
        Process.read_timer(process)
    end
  end

  # ----------------------------------------------------------------------------
  # ---  Network - Control - Methods ---
  # ----------------------------------------------------------------------------

  def cancel_block_propose(reason) do
    Logger.info("--- Cancel block propose! Reason: " <> inspect(reason))

    Enum.map(
      [
        :propose_block,
        :commit_block,
        :finalize_block,
        :cancel_block_propose,
        :cancel_block_commit
      ],
      &cancel_timer(&1)
    )

    %RoundSpecification{round_number: round_number} = RoundSpecification.get_round_specification()

    this_server = Server.get_this_server()

    data = %{
      server_id: this_server.id,
      round_number: round_number,
      reason: reason
    }

    with {:ok, private_key} <- @crypto.private_key(),
         {:ok, private_key_pem} <- ExPublicKey.pem_encode(private_key) do
      signature =
        data
        |> Poison.encode!()
        |> Crypto.sign(private_key_pem)

      Server.get_authorized_servers(false)
      |> Enum.map(fn server ->
        response =
          @http_client.post(server.url <> "/api/scheduler/cancel_block_propose", %{
            cancel_block_propose: Map.put(data, :signature, signature),
            round_specification:
              RoundSpecification.get_round_specification() |> RoundSpecification.json()
          })

        case response do
          {:ok, %{"cancel_block_propose_response" => "ok"}} ->
            :ok

          other ->
            Logger.errror(other)
        end
      end)
    end

    next_round_specification = RoundSpecification.get_next_round_specification()
    schedule(next_round_specification, :next_round)

    Logger.info(
      "-! Round canceled. Next Round will start at: " <>
        Timex.format!(next_round_specification.round_begin, "{ISO:Extended}")
    )
  end

  def cancel_block_commit(reason) do
    Logger.info("--- Cancel block commit! Reason: " <> inspect(reason))

    Enum.map(
      [
        :propose_block,
        :commit_block,
        :finalize_block,
        :cancel_block_propose,
        :cancel_block_commit
      ],
      &cancel_timer(&1)
    )

    %RoundSpecification{round_number: round_number} = RoundSpecification.get_round_specification()

    this_server = Server.get_this_server()

    data = %{
      server_id: this_server.id,
      round_number: round_number,
      reason: reason
    }

    with {:ok, private_key} <- @crypto.private_key(),
         {:ok, private_key_pem} <- ExPublicKey.pem_encode(private_key) do
      signature =
        data
        |> Poison.encode!()
        |> Crypto.sign(private_key_pem)

      Server.get_authorized_servers(false)
      |> Enum.map(fn server ->
        response =
          @http_client.post(server.url <> "/api/scheduler/cancel_block_commit", %{
            cancel_block_commit: Map.put(data, :signature, signature),
            round_specification:
              RoundSpecification.get_round_specification() |> RoundSpecification.json()
          })

        case response do
          {:ok, %{"cancel_block_commit_response" => "ok"}} ->
            :ok

          other ->
            Logger.errror(other)
        end
      end)
    end

    next_round_specification = RoundSpecification.get_next_round_specification()
    schedule(next_round_specification, :next_round)

    Logger.info(
      "-! Round canceled. Next Round will start at: " <>
        Timex.format!(next_round_specification.round_begin, "{ISO:Extended}")
    )
  end

  def handle_cancel_block_propose(
        %{
          "server_id" => server_id,
          "round_number" => incoming_round_number,
          "reason" => reason
        },
        round_specification
      ) do
    with %Server{authority: true} <- Server.get_server(server_id) do
      Logger.info("--- Recieved cancel block propose request! Reason: " <> reason)

      status =
        case reason do
          "no_transaction" ->
            # validate there a no transactions with timestamp before propose_start
            :ok

          "timeout" ->
            # compare DateTime.now() to round_times
            with %{round_number: round_number} <-
                   RoundSpecification.get_round_specification(),
                 true <- incoming_round_number >= round_number,
                 cancel_time <-
                   RoundSpecification.get_round_time(round_specification, :cancel_block_propose),
                 1 <- Timex.compare(Timex.now(), cancel_time) do
              :ok
            else
              0 -> :error
              -1 -> :error
              false -> :ok
            end

          "not_valid" ->
            :ok
        end

      case status do
        :ok ->
          Enum.map(
            [
              :propose_block,
              :commit_block,
              :finalize_block,
              :cancel_block_propose,
              :cancel_block_commit
            ],
            &cancel_timer(&1)
          )

          next_round_specification =
            RoundSpecification.set_next_round_specification(round_specification)

          # schedule the new round
          schedule(next_round_specification, :next_round)

          Logger.info(
            "-! Round canceled. Next Round will start at: " <>
              Timex.format!(next_round_specification.round_begin, "{ISO:Extended}")
          )

        :error ->
          Logger.error("-! Round cannot be canceled!")
      end
    else
      nil ->
        {:unknown_server, server_id}
    end
  end

  def handle_cancel_block_commit(
        %{
          "server_id" => server_id,
          "round_number" => incoming_round_number,
          "reason" => reason
        },
        round_specification
      ) do
    with %Server{authority: true} <- Server.get_server(server_id) do
      Logger.info("--- Recieved cancel block propose request! Reason: " <> reason)

      status =
        case reason do
          "timeout" ->
            with %{round_number: round_number} <-
                   RoundSpecification.get_round_specification(),
                 true <- incoming_round_number >= round_number,
                 cancel_time <-
                   RoundSpecification.get_round_time(round_specification, :cancel_block_commit),
                 # compare DateTime.now() to round_times
                 1 <- Timex.compare(Timex.now(), cancel_time) do
              :ok
            else
              0 -> :error
              -1 -> :error
              false -> :ok
            end

          "not_valid" ->
            :ok
        end

      case status do
        :ok ->
          Enum.map(
            [
              :propose_block,
              :commit_block,
              :finalize_block,
              :cancel_block_propose,
              :cancel_block_commit
            ],
            &cancel_timer(&1)
          )

          next_round_specification =
            RoundSpecification.set_next_round_specification(round_specification)

          # schedule the new round
          schedule(next_round_specification, :next_round)

          Logger.info(
            "-! Round canceled. Next Round will start at: " <>
              Timex.format!(next_round_specification.round_begin, "{ISO:Extended}")
          )

        :error ->
          Logger.error("-! Round cannot be canceled!")
      end
    else
      nil ->
        {:unknown_server, server_id}
    end
  end
end
