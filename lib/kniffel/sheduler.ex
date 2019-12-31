defmodule Kniffel.Sheduler do
  # in seconds
  @default_round_length 30
  # Offset (in seconds)
  @round_offset 2

  use GenServer
  alias Kniffel.{Server, Blockchain, Blockchain.Crypto, Blockchain.Block.ServerAge}
  alias DateTime
  require Logger

  def start_link(state) do
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  def init(state) do
    Process.send(self(), :prepare_node, [])
    {:ok, state}
  end

  def handle_info(:prepare_node, state) do
    Logger.info("-# Prepare and start sheduler")

    with :ok <- Blockchain.compare_block_height_with_network(),
         # compare blocks with other servers (get server adress without adding server to network)
         r when r in [:ok, :default] <-
           request_round_specification_from_network(),
         # get the round_specification for next round from master_nodes
         :ok <- Server.add_this_server_to_master_server(),
         # add server to network
         a when a in [:ok, :default] <- request_server_age_from_network(),
         # get server_age from network
         %{} = round_specification <- get_round_specification() do
      # calculate diff (in milliseconds) till start of new round
      diff_milliseconds =
        round_specification
        |> get_round_time(:round_begin)
        |> calculate_diff_to_now

      # shedule new round
      Process.send_after(self(), :next_round, diff_milliseconds)

      Logger.info(
        "-✓ Started sheduler successful! First round will start at: " <>
          Timex.format!(get_round_time(round_specification, :round_begin), "{ISO:Extended}")
      )
    else
      :error ->
        Logger.error(
          "Error while preparing to start sheduler (request data from network), repeating in 10 seconds again!"
        )

        Process.send_after(self(), :prepare_node, 10_000)

      {:error, _} ->
        Logger.error(
          "Error while preparing to start sheduler (no round_specification in cache), repeating in 10 seconds again!"
        )

        Process.send_after(self(), :prepare_node, 10_000)
    end

    {:noreply, state}
  end

  def handle_info(:next_round, state) do
    Logger.info("-> Start a new round")
    round_specification = get_round_specification()
    # get other master nodes
    servers = Server.get_authorized_servers(false)

    # do nothing if no other server in network
    if length(servers) > 0 do
      # TODO: after n rounds calculate new round times
      server = Kniffel.Server.get_this_server()

      # if this server is oldest he is choosen for block creation
      # if not he is choosen to abort if lead server runs in a timeout
      case ServerAge.is_leader?(server) do
        true ->
          round_specification
          |> schedule(:propose_block)
          |> schedule(:commit_block)
          |> schedule(:finalize_block)

        false ->
          # position = Kniffel.Blockchain.get_position_in_server_queue(server)
          round_specification
          |> schedule(:cancel_block_propose)
          |> schedule(:cancel_block_commit)
      end
    else
      Logger.info("--- No other master node found! I will shedule a new round and try again.")
      # if no other server in network save new round specification
      next_round = Kniffel.Cache.set(:round_specification, get_next_round_specification())
      # schedule the new round
      schedule(round_specification, :next_round)

      Logger.info(
        "-! Round finished. Next Round will start at: " <>
          Timex.format!(next_round.round_begin, "{ISO:Extended}")
      )
    end

    {:noreply, state}
  end

  def handle_info(:propose_block, state) do
    Logger.info("--- Propose a new block")

    case Kniffel.Blockchain.propose_new_block() do
      {:ok, _propose} ->
        :ok

      {:error, :no_transactions} ->
        cancel_block_propose(:no_transaction)
    end

    {:noreply, state}
  end

  def handle_info(:commit_block, state) do
    Logger.info("--- Commit a new block")

    case Kniffel.Blockchain.commit_new_block() do
      {:ok, _block} ->
        :ok

      {:error, :no_propose_for_block} ->
        cancel_block_commit(:not_valid)
    end

    {:noreply, state}
  end

  def handle_info(:finalize_block, state) do
    Logger.info("--- Finalize new block")
    Kniffel.Blockchain.finalize_block()
    {:noreply, state}
  end

  def handle_info(:cancel_block_propose, state) do
    Logger.info("--- Cancel block propose (timeout)")
    cancel_block_propose(:timeout)
    {:noreply, state}
  end

  def handle_info(:cancel_block_commit, state) do
    Logger.info("--- Cancel block commit (timeout)")
    cancel_block_commit(:timeout)
    {:noreply, state}
  end

  # ----------------------------------------------------------------------------
  # ---  Shedule - Methods ---
  # ----------------------------------------------------------------------------

  def schedule(round_specification, type) do
    cache_atom = (Atom.to_string(type) <> "_timer") |> String.to_atom()
    time = get_round_time(round_specification, type)

    timer = Process.send_after(self(), type, calculate_diff_to_now(time))
    Kniffel.Cache.set(cache_atom, timer, ttl: calculate_diff_to_now(time, :seconds))
    round_specification
  end

  # ----------------------------------------------------------------------------
  # ---  Helper - Methods ---
  # ----------------------------------------------------------------------------

  def cancel_timer(name) do
    cache_atom = (Atom.to_string(name) <> "_timer") |> String.to_atom()

    Kniffel.Cache.take(cache_atom)
    |> Process.cancel_timer()
  end

  def read_timer(name) do
    cache_atom = (Atom.to_string(name) <> "_timer") |> String.to_atom()

    Kniffel.Cache.get(cache_atom)
    |> Process.read_timer()
  end

  defp get_round_time(%{round_begin: round_begin}, :round_begin) do
    round_begin
  end

  defp get_round_time(%{round_begin: round_begin, round_length: round_length}, :next_round) do
    duration = Timex.Duration.from_seconds(round_length + @round_offset)
    Timex.add(round_begin, duration)
  end

  defp get_round_time(%{round_begin: round_begin, round_length: round_length}, :propose_block) do
    duration =
      round_length
      |> Timex.Duration.from_seconds()
      |> Timex.Duration.scale(1 / 3)

    Timex.add(round_begin, duration)
  end

  defp get_round_time(%{round_begin: round_begin, round_length: round_length}, :commit_block) do
    duration =
      round_length
      |> Timex.Duration.from_seconds()
      |> Timex.Duration.scale(2 / 3)

    Timex.add(round_begin, duration)
  end

  defp get_round_time(round_specification, :cancel_block_propose),
    do: get_round_time(round_specification, :propose_block)

  defp get_round_time(round_specification, :cancel_block_commit),
    do: get_round_time(round_specification, :commit_block)

  defp get_round_time(_round_specification, _name), do: nil

  defp calculate_diff_to_now(time, unit \\ :milliseconds) do
    Timex.diff(time, Timex.now(), unit)
  end

  defp get_round_specification() do
    case Kniffel.Cache.get(:round_specification) do
      %{
        round_length: _round_length,
        round_number: _round_number,
        round_begin: _round_begin
      } = round_specification ->
        round_specification

      nil ->
        {:error, :no_round_specification_in_cache}
    end
  end

  defp get_default_round_specification() do
    time_now =
      Timex.add(
        Timex.now(),
        Timex.Duration.from_seconds(@default_round_length + @round_offset)
      )

    %{
      round_length: @default_round_length,
      round_begin: time_now,
      round_number: 1
    }
  end

  defp request_round_specification_from_network() do
    servers = Server.get_authorized_servers(false)

    round_specification_responses =
      Enum.map(servers, fn server ->
        with {:ok, %{"round_response" => round_response}} <-
               Kniffel.Request.get(server.url <> "/api/sheduler/next_round") do
          {:ok, round_begin} = Timex.parse(round_response["round_begin"], "{ISO:Extended}")

          case Timex.compare(Timex.now(), round_begin) do
            -1 ->
              %{
                round_length: round_response["round_length"],
                round_begin: round_begin,
                round_number: round_response["round_number"]
              }

            0 ->
              nil

            1 ->
              nil
          end
        else
          {:error, _error} ->
            nil
        end
      end)

    # if no server is in network empty list is returned
    # otherwise answers will be grouped and answer with highest count is choosen
    with false <- Enum.empty?(round_specification_responses),
         uniq_specs <- Enum.uniq(round_specification_responses),
         grouped_specs <-
           Enum.map(uniq_specs, fn uniq_spec ->
             {uniq_spec, Enum.count(round_specification_responses, &(uniq_spec == &1))}
           end),
         sort_specs <- Enum.sort_by(grouped_specs, &elem(&1, 1), &>=/2) do
      {round_specification, _count} = List.first(sort_specs)

      if round_specification do
        Kniffel.Cache.set(:round_specification, round_specification)
        :ok
      else
        Kniffel.Cache.set(:round_specification, get_default_round_specification())
        :default
      end
    else
      true ->
        Kniffel.Cache.set(:round_specification, get_default_round_specification())
        :default
    end
  end

  def request_server_age_from_network() do
    servers = Server.get_authorized_servers(false)

    server_age_responses =
      Enum.map(servers, fn server ->
        with {:ok, %{"server_age" => server_age}} <-
               Kniffel.Request.get(server.url <> "/api/sheduler/server_age") do
          ages = Enum.map(server_age["ages"], fn {server_id, age} -> {server_id, age} end)

          offsets =
            Enum.map(server_age["offsets"], fn {server_id, offset} -> {server_id, offset} end)

          %{ages: ages, checked_at_block: server_age["checked_at_block"], offsets: offsets}
        else
          {:error, _error} ->
            nil
        end
      end)

    # if no server is in network empty list is returned
    # otherwise answers will be grouped and answer with highest count is choosen
    with false <- Enum.empty?(server_age_responses),
         unique_ages <- Enum.uniq(server_age_responses),
         grouped_ages <-
           Enum.map(unique_ages, fn unique_age ->
             {unique_age, Enum.count(server_age_responses, &(unique_age == &1))}
           end),
         sort_ages <- Enum.sort_by(grouped_ages, &elem(&1, 1), &>=/2) do
      {server_age, _count} = List.first(sort_ages)

      if server_age do
        Kniffel.Cache.set(:server_age, server_age)
        :ok
      else
        ServerAge.get_server_age()
        :default
      end
    else
      true ->
        ServerAge.get_server_age()
        :default
    end
  end

  # ----------------------------------------------------------------------------
  # ---  Network - Control - Methods ---
  # ----------------------------------------------------------------------------

  def get_next_round_specification() do
    with %{
           round_length: round_length,
           round_number: round_number
         } = round_specification <- Kniffel.Cache.get(:round_specification) do
      new_round_begin = get_round_time(round_specification, :next_round)

      %{
        round_length: round_length,
        round_begin: new_round_begin,
        round_number: round_number + 1
      }
    else
      nil ->
        {:error, :no_round_specification_in_cache}
    end
  end

  def cancel_block_propose(reason) do
    %{round_number: round_number} = get_round_specification()
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
        {:ok, %{"cancel_block_propose_response" => :ok}} =
          Kniffel.Request.post(server.url <> "/api/sheduler/cancel_block_propose", %{
            cancel_block_propose: Map.put(data, :signature, signature)
          })
      end)
    end
  end

  def cancel_block_commit(reason) do
    %{round_number: round_number} = get_round_specification()
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
        {:ok, %{"cancel_block_commit_response" => :ok}} =
          Kniffel.Request.post(server.url <> "/api/sheduler/cancel_block_commit", %{
            cancel_block_commit: Map.put(data, :signature, signature)
          })
      end)
    end
  end

  def handle_cancel_block_propose(%{
        "server_id" => server_id,
        "round_number" => incoming_round_number,
        "reason" => reason
      }) do
    with %Server{authority: true} <- Server.get_server(server_id) do
      case reason do
        :no_transaction ->
          # validate there a no transactions with timestamp before propose_start
          # Kniffel.Blockchain.validate_no_transaction()
          # cancel timers and wait for next round
          Enum.map(
            [
              :propose_block,
              :create_block,
              :finalize_block,
              :cancel_block_propose,
              :cancel_block_commit
            ],
            &cancel_timer(&1)
          )

          :ok

        :timeout ->
          # compare DateTime.now() to round_times
          with %{round_number: round_number} = round_specification <- get_round_specification(),
               true = incoming_round_number == round_number,
               cancel_time <- get_round_time(round_specification, :cancel_block_propose),
               1 <- Timex.compate(Timex.now(), cancel_time) do
            Enum.map(
              [
                :propose_block,
                :create_block,
                :finalize_block,
                :cancel_block_propose,
                :cancel_block_commit
              ],
              &cancel_timer(&1)
            )

            Logger.info(
              "--- Recieved cancel block propose request! Reason: " <> Atom.to_string(reason)
            )

            # if no other server in network save new round specification
            next_round = Kniffel.Cache.set(:round_specification, get_next_round_specification())
            # schedule the new round
            schedule(round_specification, :next_round)

            Logger.info(
              "-! Round canceled. Next Round will start at: " <>
                Timex.format!(next_round.round_begin, "{ISO:Extended}")
            )

            :ok
          else
            0 -> :error
            -1 -> :error
            false -> :error
          end

        :not_valid ->
          # cancel timers and wait for next round
          Enum.map(
            [
              :propose_block,
              :create_block,
              :finalize_block,
              :cancel_block_propose,
              :cancel_block_commit
            ],
            &cancel_timer(&1)
          )

          :ok
      end
    else
      nil ->
        {:unknown_server, server_id}
    end
  end

  def handle_cancel_block_commit(%{
        "server_id" => server_id,
        "round_number" => _round_number,
        "reason" => reason
      }) do
    with %Server{authority: true} <- Server.get_server(server_id) do
      case reason do
        :timeout ->
          # compare DateTime.now() to round_times
          with %{round_number: round_number} = round_specification <- get_round_specification(),
               true = incoming_round_number == round_number,
               cancel_time <- get_round_time(round_specification, :cancel_block_commit),
               1 <- Timex.compate(Timex.now(), cancel_time) do
            Enum.map(
              [
                :propose_block,
                :create_block,
                :finalize_block,
                :cancel_block_propose,
                :cancel_block_commit
              ],
              &cancel_timer(&1)
            )

            Logger.info(
              "--- Recieved cancel block propose request! Reason: " <> Atom.to_string(reason)
            )

            # if no other server in network save new round specification
            next_round = Kniffel.Cache.set(:round_specification, get_next_round_specification())
            # schedule the new round
            schedule(round_specification, :next_round)

            Logger.info(
              "-! Round canceled. Next Round will start at: " <>
                Timex.format!(next_round.round_begin, "{ISO:Extended}")
            )

            :ok
          else
            0 -> :error
            -1 -> :error
            false -> :error
          end

          :ok

        :not_valid ->
          # cancel timers and wait for next round
          :ok
      end
    else
      nil ->
        {:unknown_server, server_id}
    end
  end
end
