defmodule Kniffel.Cache do
  use Nebulex.Cache,
    otp_app: :kniffel,
    adapter: Nebulex.Adapters.Local
end
