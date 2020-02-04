defmodule Kniffel.ServerTest do
  use Kniffel.DataCase

  alias Kniffel.Server

  import Kniffel.Factory

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

  describe "Server.create_server" do
    test "server_created" do
      server_url = "example.com"
      server = insert(:server, url: "https://kniffel.app", authority: true)
      server = insert(:server, authority: false)

      server_key = Kniffel.CryptoHelper.create_rsa_key()

      Kniffel.Cache.set({server_url, "/api/servers/this"}, {:ok, %{"server" => %{"id" => server_key.id, "url" => "https://" <> server_url, "public_key" => server_key.public_pem_string, "authority" => true}}})

      Kniffel.Cache.set({server_url, "/api/servers"}, {:ok, "Server already known."})

      Kniffel.Cache.set({server_url, "/api/servers", :params}, %{
        server: %{
          url: System.get_env("URL")
        }
      })

      Server.create_server(%{
        "url" => "https://" <> server_url
      })
    end
  end

  describe "Server.create_authority_server" do
    test "server_created" do
      server_url = "tobiashoge.de"
      server = insert(:server, url: "https://kniffel.app", authority: true)
      insert(:server, authority: false)

      IO.inspect(Server.get_servers())

      server_key = Kniffel.CryptoHelper.create_rsa_key()

      Kniffel.Cache.set({server_url, "/api/servers/this"}, {:ok, %{"server" => %{"id" => server_key.id, "url" => "https://" <> server_url, "public_key" => server_key.public_pem_string, "authority" => true}}})

      Kniffel.Cache.set({server_url, "/api/servers"}, {:ok, "Server already known."})

      Kniffel.Cache.set({server_url, "/api/servers", :params}, %{
        server: %{
          url: System.get_env("URL")
        }
      })



      Kniffel.Cache.set({"kniffel.app", "/api/servers", :params}, %{
        server: %{
          url: "https://" <> server_url
        }
      })
      Kniffel.Cache.set({"tobiashoge.de", "/api/servers", :params}, %{
        server: %{
          url: "https://" <> server_url
        }
      })

      Kniffel.Cache.set({"kniffel.app", "/api/servers"}, {:ok, "Server already known."})

      Kniffel.Cache.set({"tobiashoge.de", "/api/servers"}, {:ok, "Server already known."})

      Server.create_server(%{
        "url" => "https://" <> server_url
      })
    end
  end
end
