use Mix.Config

# Configure your database
config :kniffel, Kniffel.Repo, pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :kniffel, KniffelWeb.Endpoint,
  http: [port: 4002],
  server: false,
  secret_key_base: "UrwGy41yrDwJsejSAcTrlVTIbyAUDZzIT5LQheRbcE6tltjuHKSnONcHvlX9+BwY"

config :kniffel, :request, Kniffel.RequestMock
config :kniffel, :crypto, Kniffel.CryptoMock
config :kniffel, :round_endpoint, Kniffel.BlockchainMock

# Print only warnings and errors during test
config :logger, level: :warn
