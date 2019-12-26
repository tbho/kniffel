defmodule Kniffel.Sheduler do
  # use Quantum.Scheduler,
  #   otp_app: :kniffel

  use GenServer

  def start_link(state) do
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  def init(state) do
    # schedule_block_creation()
    roundtime = get_round_time()
    schedule_block_proposal(Kernel.trunc(roundtime / 3))
    {:ok, state}
  end

  def handle_info(:new_round, state) do
    roundtime = get_round_time()
    server = Kniffel.Server.get_this_server()

    if Kniffel.Blockchain.is_leader?(server) do
      Process.send(self(), :propose_block)
      schedule_block_commit(Kernel.trunc(roundtime / 3))
      schedule_block_finalization(Kernel.trunc(roundtime / 3) * 2)
    else
      schedule_cancel_block_propose(Kernel.trunc(roundtime / 3))
      schedule_cancel_block_commit(Kernel.trunc(roundtime / 3) * 2)
    end

    schedule_round_begin(roundtime)
    {:noreply, state}
  end

  def handle_info(:propose_block, state) do
    Kniffel.Blockchain.propose_new_block()
    {:noreply, state}
  end

  def handle_info(:commit_block, state) do
    case Kniffel.Blockchain.commit_new_block() do
      {:ok, _block} ->
        :ok

      {:error, :no_propose_for_block} ->
        Kniffel.Blockchain.cancel_block_commit()
    end

    {:noreply, state}
  end

  def handle_info(:finalize_block, state) do
    Kniffel.Blockchain.finalize_block()
    {:noreply, state}
  end

  def handle_info(:cancel_block_propose, state) do
    Kniffel.Blockchain.cancel_block_propose()
    {:noreply, state}
  end

  def handle_info(:cancel_block_commit, state) do
    Kniffel.Blockchain.cancel_block_commit()
    {:noreply, state}
  end

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

  def cancel_timer(name) do
    Kniffel.Cache.take(name)
    |> Process.cancel_timer()
  end

  def read_timer(name) do
    Kniffel.Cache.get(name)
    |> Process.read_timer()
  end

  defp get_round_time() do
    roundtime =
      case Kniffel.Cache.get(:round_time) do
        nil ->
          round_time = Kniffel.Blockchain.get_last_round_time()
          Kniffel.Cache.set(:round_time, round_time)
          round_time

        hit ->
          hit
      end
  end
end
