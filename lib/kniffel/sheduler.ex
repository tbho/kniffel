defmodule Kniffel.Sheduler do
  # use Quantum.Scheduler,
  #   otp_app: :kniffel

  use GenServer

  def start_link(state) do
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  def init(state) do
    # schedule_block_creation()
    schedule_block_proposal(60)
    {:ok, state}
  end

  def handle_info(:create_block, state) do
    Kniffel.Blockchain.create_new_block()
    {:noreply, state}
  end

  def handle_info(:propose_block, state) do
    Kniffel.Blockchain.propose_new_block()
    {:noreply, state}
  end

  def handle_info(:finalize_block, state) do
    Kniffel.Blockchain.finalize_block()
    {:noreply, state}
  end

  def schedule_block_proposal(seconds) do
    # In 1 minute
    timer = Process.send_after(self(), :propose_block, seconds * 1000)
    Kniffel.Cache.set(:propose_block_timer, timer, ttl: seconds)
    timer
  end

  def schedule_finalize_block(seconds) do
    # In 1 minute
    timer = Process.send_after(self(), :finalize_block, seconds * 1000)
    Kniffel.Cache.set(:finalize_block_timer, timer, ttl: seconds)
    timer
  end

  def schedule_block_creation(seconds) do
    # In 1 minute
    timer = Process.send_after(self(), :create_block, seconds * 1000)
    Kniffel.Cache.set(:create_block_timer, timer, ttl: seconds)
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
end
