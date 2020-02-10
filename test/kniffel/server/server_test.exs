defmodule Kniffel.ServerTest do
  use Kniffel.DataCase

  alias Kniffel.Server

  import Kniffel.Factory

  import Mox

  def flush_cache(_context) do
    Kniffel.Cache.flush()
    :ok
  end

  setup :flush_cache
  setup :verify_on_exit!

  describe "Server.create_server" do
    test "server_created" do
      insert(:this_server)
      insert(:server, url: "https://kniffel.app", authority: true)
      insert(:server)

      server_key = Kniffel.CryptoHelper.create_rsa_key()

      Kniffel.RequestMock
      |> expect(:get, fn "https://example.com/api/servers/this" ->
        {:ok,
         %{
           "server" => %{
             "id" => server_key.id,
             "url" => "https://example.com",
             "public_key" => server_key.public_pem_string,
             "authority" => true
           }
         }}
      end)

      Kniffel.RequestMock
      |> expect(:post, fn "https://example.com/api/servers",
                          %{
                            server: %{
                              url: "https://tobiashoge.de"
                            }
                          } ->
        {:ok, "Server already known."}
      end)

      Server.create_server(%{
        "url" => "https://example.com"
      })
    end
  end

  describe "Server.create_authority_server" do
    test "server_created" do
      insert(:this_server)
      insert(:server, url: "https://this.server", authority: true)
      insert(:server)
      insert(:block)

      this_server = Kniffel.Server.get_this_server()

      server_key = Kniffel.CryptoHelper.create_rsa_key()

      Kniffel.RequestMock
      |> expect(:get, fn "https://kniffel.app/api/servers/this" ->
        {:ok,
         %{
           "server" => %{
             "id" => server_key.id,
             "url" => "https://kniffel.app",
             "public_key" => server_key.public_pem_string,
             "authority" => true
           }
         }}
      end)

      Kniffel.RequestMock
      |> expect(:post, 3, fn server_url, params ->
        case {server_url, params} do
          {"https://kniffel.app/api/servers",
           %{
             server: %{
               url: "https://tobiashoge.de"
             }
           }} ->
            {:ok, "Server already known."}

          {"https://kniffel.app/api/servers",
           %{
             server: %{
               url: "https://kniffel.app"
             }
           }} ->
            {:ok, "Server already known."}

          {"https://this.server/api/servers",
           %{
             server: %{
               url: "https://kniffel.app"
             }
           }} ->
            {:ok, "Server already known."}
        end
      end)

      Server.create_server(%{
        "url" => "https://kniffel.app"
      })
    end
  end
end
