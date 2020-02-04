defmodule Kniffel.UserTest do
  use Kniffel.DataCase

  alias Kniffel.User

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
    |> Kniffel.Server.cast_changeset(%{
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

  describe "User.get_user_from_server" do
    test "request_ok user_inserted" do
      # start_supervised(Kniffel.Cache)

      user_key = Kniffel.CryptoHelper.create_rsa_key()

      id = user_key.id
      server_url = "kniffel.app"
      path = "/api/users/" <> id

      Kniffel.Cache.set(
        {server_url, path},
        {:ok,
         %{
           "user" => %{
             "id" => user_key.id,
             "user_name" => "tbho",
             "public_key" => user_key.public_pem_string
           }
         }}
      )

      assert %User{} = User.get_user_from_server(id, "https://" <> server_url)

      assert Enum.count(User.get_users()) == 1
    end

    test "request_error" do
      user_key = Kniffel.CryptoHelper.create_rsa_key()

      id = user_key.id
      server_url = "kniffel.app"
      path = "/api/users/" <> id

      Kniffel.Cache.set(
        {server_url, path},
        {:error,
         %{
           error: "not_found"
         }}
      )

      User.get_user_from_server(id, "https://" <> server_url)
    end
  end

  describe "User.create_user" do
    test "user_created" do
      server_url = "kniffel.app"
      path = "/api/users"

      %Kniffel.Server{}
      |> Kniffel.Server.cast_changeset(%{
        "url" => "https://" <> server_url,
        "public_key" => "123",
        "authority" => false,
        "id" => "123"
      })
      |> Repo.insert()

      Kniffel.Cache.set({server_url, path, :params}, %{
        user: %{
          id: "dab28baffc1e390792f1506ac9cc733fba8fed887e187a1bf61bba1193de0f86",
          user_name: "tbho",
          public_key: ""
        }
      })

      Kniffel.Cache.set({server_url, path}, {:ok, "accept"})

      User.create_user(%{
        "private_key" => "",
        "password" => "Test123!",
        "password_confirmation" => "Test123!",
        "user_name" => "tbho"
      })
    end

    test "user_created with own private key" do
      server_url = "kniffel.app"
      path = "/api/users"

      user_key = Kniffel.CryptoHelper.create_rsa_key()
      server_key = Kniffel.CryptoHelper.create_rsa_key()

      %Kniffel.Server{}
      |> Kniffel.Server.cast_changeset(%{
        "url" => "https://" <> server_url,
        "public_key" => server_key.public_pem_string,
        "authority" => false,
        "id" => "123"
      })
      |> Repo.insert()

      Kniffel.Cache.set({server_url, path, :params}, %{
        user: %{
          id: user_key.id,
          user_name: "tbho",
          public_key: user_key.public_pem_string
        }
      })

      Kniffel.Cache.set({server_url, path}, {:ok, "accept"})

      User.create_user(%{
        "private_key" => user_key.private_pem_string,
        "password" => "Test123!",
        "password_confirmation" => "Test123!",
        "user_name" => "tbho"
      })
    end
  end

  describe "User.preload_private_key" do
    test "load_key ok" do
      user_key = Kniffel.CryptoHelper.create_rsa_key()

      user_params = %{
        "private_key" => user_key.private_pem_string,
        "password" => "Test123!",
        "password_confirmation" => "Test123!",
        "user_name" => "tbho"
      }

      {:ok, user} =
        %User{}
        |> User.change_user(user_params)
        |> Repo.insert()

      assert %User{} = user = User.preload_private_key(user, user_params["password"])
      assert user.private_key == user_key.private_pem_string
    end

    test "load_key wrong_password" do
      user_key = Kniffel.CryptoHelper.create_rsa_key()

      user_params = %{
        "private_key" => user_key.private_pem_string,
        "password" => "Test123!",
        "password_confirmation" => "Test123!",
        "user_name" => "tbho"
      }

      {:ok, user} =
        %User{}
        |> User.change_user(user_params)
        |> Repo.insert()

      assert {:error, :could_not_load} = User.preload_private_key(user, "wrong_password")
    end
  end

  describe "User.get_user" do
    test "ok" do
      user_key = Kniffel.CryptoHelper.create_rsa_key()

      user_params = %{
        "private_key" => user_key.private_pem_string,
        "password" => "Test123!",
        "password_confirmation" => "Test123!",
        "user_name" => "tbho"
      }

      %User{}
      |> User.change_user(user_params)
      |> Repo.insert()

      assert %User{} = User.get_user(user_key.id)
    end

    test "wrong_id" do
      assert is_nil(User.get_user("wrong_id"))
    end
  end

  describe "User.get_users" do
    test "ok" do
      user_key1 = Kniffel.CryptoHelper.create_rsa_key()
      user_key2 = Kniffel.CryptoHelper.create_rsa_key()

      user_params1 = %{
        "private_key" => user_key1.private_pem_string,
        "password" => "Test123!",
        "password_confirmation" => "Test123!",
        "user_name" => "tbho1"
      }

      user_params2 = %{
        "private_key" => user_key2.private_pem_string,
        "password" => "Test123!",
        "password_confirmation" => "Test123!",
        "user_name" => "tbho2"
      }

      %User{}
      |> User.change_user(user_params1)
      |> Repo.insert()

      %User{}
      |> User.change_user(user_params2)
      |> Repo.insert()

      assert Enum.count(User.get_users()) == 2
    end

    test "no_users" do
      assert [] = User.get_users()
    end
  end

  describe "User.json" do
    test "ok" do
      user = %User{id: "123", public_key: "abcde", user_name: "test"}

      assert %{id: "123", public_key: "abcde", user_name: "test"} = User.json(user)
    end

    test "wrong argument" do
      assert is_nil(User.json(nil))
      assert is_nil(User.json(%{}))
      assert is_nil(User.json([]))
    end
  end
end
