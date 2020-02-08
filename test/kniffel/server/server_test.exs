defmodule Kniffel.ServerTest do
  use Kniffel.DataCase

  alias Kniffel.Server

  import Kniffel.Factory

  import Mox

  def start_cache(_context) do
    start_supervised(Kniffel.Cache)
    :ok
  end

  def insert_this_server(_context) do
    {:ok, private_key} = Kniffel.Blockchain.Crypto.private_key()
    {:ok, public_key} = ExPublicKey.public_key_from_private_key(private_key)
    {:ok, pem_string} = ExPublicKey.pem_encode(public_key)
    id = ExPublicKey.RSAPublicKey.get_fingerprint(public_key)

    %Kniffel.Server{}
    |> Kniffel.Server.change_server(%{
      "url" => System.get_env("URL"),
      "public_key" => pem_string,
      "authority" => false,
      "id" => id
    })
    |> Repo.insert()

    :ok
  end

  setup :start_cache
  setup :insert_this_server
  setup :verify_on_exit!

  describe "Server.create_server" do
    test "server_created" do
      insert(:server, url: "https://kniffel.app", authority: true)
      insert(:server, authority: false)

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
                              url: "http://hoge.cloud:3000"
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
      insert(:server, url: "https://kniffel.app", authority: true)
      insert(:server, authority: false)
      insert(:block)

      server_key = Kniffel.CryptoHelper.create_rsa_key()

      Kniffel.RequestMock
      |> expect(:get, fn "https://tobiashoge.de/api/servers/this" ->
        {:ok,
         %{
           "server" => %{
             "id" => server_key.id,
             "url" => "https://tobiashoge.de",
             "public_key" => server_key.public_pem_string,
             "authority" => true
           }
         }}
      end)

      Kniffel.RequestMock
      |> expect(:post, fn "https://tobiashoge.de/api/servers",
                          %{
                            server: %{
                              url: "http://hoge.cloud:3000"
                            }
                          } ->
        {:ok, "Server already known."}
      end)

      Kniffel.RequestMock
      |> expect(:post, fn "https://kniffel.app/api/servers",
                          %{
                            server: %{
                              url: "https://tobiashoge.de"
                            }
                          } ->
        {:ok, "Server already known."}
      end)

      Kniffel.RequestMock
      |> expect(:post, fn "https://tobiashoge.de/api/servers",
                          %{
                            server: %{
                              url: "https://tobiashoge.de"
                            }
                          } ->
        {:ok, "Server already known."}
      end)

      Server.create_server(%{
        "url" => "https://tobiashoge.de"
      })
    end
  end
end
