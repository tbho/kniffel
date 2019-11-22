defmodule Kniffel.Blockchain.Block do
  alias Kniffel.Blockchain.Crypto
  alias Kniffel.Blockchain.Block

  use Ecto.Schema
  import Ecto.Changeset

  # Specify which fields to hash in a block
  @sign_fields [:index, :data, :pre_hash]
  @hash_fields [:user_id, :timestamp, :signature, :proof | @sign_fields]

  @primary_key {:index, :id, autogenerate: false}
  @foreign_key_type :index

  schema "block" do
    field :pre_hash, :string
    field :proof, :integer, default: 1
    field :timestamp, :utc_datetime, default: DateTime.truncate(DateTime.utc_now(), :second)
    field :hash, :string
    field :signature, :string
    field :data, :string

    belongs_to(:user, Kniffel.User, type: :string)
    has_many(:transactions, Kniffel.Blockchain.Transaction)
  end

  # @doc false
  # def changeset_p2p(block, attrs) do
  #   block
  #   |> cast(attrs, [:pre_hash, :transactions, :index])
  #   |> cast(attrs, [:proof, :timestamp, :creator, :hash, :signature])
  #   |> put_assoc(:transactions, attrs["transactions"] || block.transactions)
  #   |> verify_changeset
  # end

  @doc false
  def changeset_create(block, attrs) do
    block
    |> cast(attrs, [:pre_hash, :data, :index])
    |> put_assoc(:transactions, attrs.transactions || block.transactions)
    |> sign_changeset()
    |> hash_changeset
  end

  def valid?(%Block{} = block) do
    Crypto.hash(block) == block.hash
  end

  def valid?(%Block{} = block, %Block{} = pre_block) do
    block.pre_hash == pre_block.hash && valid?(block)
  end

  def sign_changeset(%Ecto.Changeset{} = changeset) do
    with {:ok, private_key} <- Crypto.private_key(),
         {:ok, private_key_pem} <- ExPublicKey.pem_encode(private_key),
         {:ok, rsa_pub_key} <- ExPublicKey.public_key_from_private_key(private_key),
         user_id <- ExPublicKey.RSAPublicKey.get_fingerprint(rsa_pub_key) do
      changeset =
        changeset
        |> cast(%{user_id: user_id}, [:user_id])

      signature =
        changeset
        |> take(@sign_fields)
        |> Poison.encode!()
        |> Crypto.sign(private_key_pem)

      changeset
      |> put_change(:signature, signature)
    end
  end

  @doc "Calculate and put the hash in the block"
  def hash_changeset(%Ecto.Changeset{} = changeset) do
    pow_changeset("", changeset)
  end

  def pow_changeset(correct_hash = "00" <> _, %Ecto.Changeset{} = changeset) do
    put_change(changeset, :hash, correct_hash)
  end

  def pow_changeset(wrong_hash, %Ecto.Changeset{} = changeset) do
    {_, proof} = fetch_field(changeset, :proof)

    changeset =
      changeset
      |> put_change(:proof, proof + 1)
      |> put_change(:timestamp, DateTime.truncate(DateTime.utc_now(), :second))

    changeset
    |> take(@hash_fields)
    |> Poison.encode!()
    |> Crypto.hash()
    |> IO.inspect()
    |> pow_changeset(changeset)
  end

  defp take(%Ecto.Changeset{} = changeset, fields) do
    Enum.reduce(fields, %{}, fn field, map ->
      case fetch_field(changeset, field) do
        {_, data} ->
          Map.put(map, field, data)
      end
    end)
  end

  # @doc "Verify a block using the public key present in it"
  # def verify_changeset(%Ecto.Changeset{} = changeset) do
  #   signature = fetch_field(changeset, :signature)
  #   creator = fetch_field(changeset, :creator)

  #   case Crypto.verify(signature, creator, take(changeset, @sign_fields)) do
  #     :ok ->
  #       changeset

  #     :invalid ->
  #       add_error(changeset, :hash, "invalid",
  #         additional: "hash is not valid for the other fields"
  #       )
  #   end
  # end

  # @doc "Verify a block using the public key present in it"
  # def verify_block(%Block{} = block) do
  #   Crypto.verify(block.signature, block.creator, Map.take(block, @sign_fields))
  # end

  # def sign!(block, private_key) do
  #   signature =
  #   block
  #   |> Map.take(@sign_fields)
  #   |> Crypto.sign(private_key)

  #   block
  #   |> Map.put(:signature, signature)
  #   |> Map.put(:creator, Crypto.public_key(private_key))
  # end

  #  @doc "Calculate and put the hash in the block"
  #  def hash!(%Block{} = block) do
  #    correct_hash = consensus(block)
  #    %{block | hash: correct_hash}
  #  end

  #  def consensus(%Block{} = block) do
  #    poc("", block)
  #  end

  #  def poc(correct_hash = "0000" <> _, _) do
  #    correct_hash
  #  end

  #  def poc(wrong_hash, %{proof: proof} = block) do
  #    block = %{block | proof: proof + 1}

  #    block
  #    |> Map.take(@hash_fields)
  #    |> Crypto.hash()
  #    |> poc(block)
  #  end
end
