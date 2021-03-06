defmodule Kniffel.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    # List all child processes to be supervised
    children = [
      # Start the Nebulex Cache
      Kniffel.Cache,
      # Start the Ecto repository
      Kniffel.Repo,
      # Start the endpoint when the application starts
      KniffelWeb.Endpoint,
      # Starts the sheduling service for proposal and creation of new blocks
      Kniffel.Scheduler
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Kniffel.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    KniffelWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
