defmodule Kniffel.Factory do
  # with Ecto
  use ExMachina.Ecto, repo: Kniffel.Repo
  import Mox

  @standard_password "Test123!"

  def not_correct_signed_transaction_factory do
    %Kniffel.Blockchain.Transaction{
      id: Ecto.UUID.generate(),
      timestamp: Timex.now() |> Timex.format!("{ISO:Extended}"),
      data: Poison.encode!(%{"games" => [], "scores" => []}),
      signature: "test",
      block_index: nil,
      user_id: nil
    }
  end

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

  # def private_user_gen_id_factory do
  #   %Kniffel.User{
  #     user_name: "tbho"
  #   }
  #   |> Kniffel.User.change_user(%{
  #     "password" => @standard_password,
  #     "password_confirmation" => @standard_password,
  #     "private_key" => ""
  #   })
  #   |> Ecto.Changeset.apply_changes()
  # end

  # def public_user_factory do
  #   user_key = Kniffel.CryptoHelper.create_rsa_key()

  #   %Kniffel.User{
  #     user_name: "tbho"
  #   }
  #   |> Kniffel.User.change_user(%{
  #     "public_key" => user_key.public_pem_string
  #   })
  #   |> Ecto.Changeset.apply_changes()
  # end

  def server_factory do
    server_key = Kniffel.CryptoHelper.create_rsa_key()

    %Kniffel.Server{
      url: "https://test.de",
      public_key: server_key.public_pem_string,
      authority: false,
      id: server_key.id
    }
  end

  def this_server_factory do
    {:ok, private_key} = ExPublicKey.generate_key(4096)

    Kniffel.CryptoMock
    |> stub(:private_key, fn -> {:ok, private_key} end)

    %{public_pem_string: public_pem_string, id: id} =
      Kniffel.CryptoHelper.generate_fields_from_rsa_key(private_key)

    %Kniffel.Server{
      url: "https://tobiashoge.de",
      public_key: public_pem_string,
      authority: true,
      id: id
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

  def block_factory do
    %Kniffel.Blockchain.Block{}
    |> Kniffel.Blockchain.Block.changeset_create(%{
      data:
        Poison.encode!(%{
          "propose" => [],
          "propose_response" => [],
          "transactions" => []
        }),
      pre_hash: "ZERO_HASH",
      index: 0,
      transactions: []
    })
    |> Ecto.Changeset.apply_changes()
  end

  def signed_block_factory(attrs) do
    %Kniffel.Blockchain.Block{}
    |> Kniffel.Blockchain.Block.changeset_create(%{
      data: attrs.data,
      pre_hash: attrs.block.hash,
      index: attrs.block.index + 1,
      transactions: attrs.transactions
    })
    |> Ecto.Changeset.apply_changes()
  end
end
