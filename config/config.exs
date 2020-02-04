# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
use Mix.Config

config :kniffel,
  ecto_repos: [Kniffel.Repo]

config :kniffel, Kniffel.Repo,
  pool_size: 10,
  log: false

# Configures the endpoint
config :kniffel, KniffelWeb.Endpoint,
  http: [:inet6, port: 4000],
  url: [host: "localhost"],
  render_errors: [view: KniffelWeb.ErrorView, accepts: ~w(html json)],
  pubsub: [name: Kniffel.PubSub, adapter: Phoenix.PubSub.PG2]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :phoenix, :template_engines,
  slim: PhoenixSlime.Engine,
  slime: PhoenixSlime.Engine

# config :kniffel, Kniffel.Cache,

config :kniffel, :request, Kniffel.Request.HTTPoison

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
