defmodule Kniffel.Repo do
  use Ecto.Repo,
    otp_app: :kniffel,
    adapter: Ecto.Adapters.Postgres
end
