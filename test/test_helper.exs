ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Kniffel.Repo, :manual)
{:ok, _} = Application.ensure_all_started(:ex_machina)
Mox.defmock(Kniffel.RequestMock, for: Kniffel.Request)
