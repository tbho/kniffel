defmodule Kniffel.Factory do
  # with Ecto
  use ExMachina.Ecto, repo: Kniffel.Repo

  @standard_password "Test123!"

  def private_user_factory do
    user_key = Kniffel.CryptoHelper.create_rsa_key()

    %Kniffel.User{
      user_name: "tbho"
    }
    |> Kniffel.User.change_user(%{
      "password" => @standard_password,
      "password_confirmation" => @standard_password,
      "private_key" => user_key.private_pem_string
    })
    |> Ecto.Changeset.apply_changes()
  end

  def private_user_gen_id_factory do
    %Kniffel.User{
      user_name: "tbho"
    }
    |> Kniffel.User.change_user(%{
      "password" => @standard_password,
      "password_confirmation" => @standard_password,
      "private_key" => ""
    })
    |> Ecto.Changeset.apply_changes()
  end

  def public_user_factory do
    user_key = Kniffel.CryptoHelper.create_rsa_key()

    %Kniffel.User{
      user_name: "tbho"
    }
    |> Kniffel.User.change_user(%{
      "public_key" => user_key.public_pem_string
    })
    |> Ecto.Changeset.apply_changes()
  end

  def server_factory do
    server_key = Kniffel.CryptoHelper.create_rsa_key()

    %Kniffel.Server{
      url: "https://test.de",
      public_key: server_key.public_pem_string,
      authority: false,
      id: server_key.id
    }
  end

  def session_factory do
    %Kniffel.User.Session{
      user: build(:private_user),
      ip: "127.0.0.1",
      user_agent: "Test",
      access_token: "secret_access_token",
      access_token_issued_at: DateTime.utc_now(),
      refresh_token: "secret_refresh_token",
      refresh_token_issued_at: DateTime.utc_now()
    }
  end
end
