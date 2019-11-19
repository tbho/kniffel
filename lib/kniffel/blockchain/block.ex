defmodule Kniffel.Blockchain.Block do
  alias Kniffel.Blockchain.Crypto
  alias Kniffel.Blockchain.Block

  use Ecto.Schema
  import Ecto.Changeset

  # Specify which fields to hash in a block
  @sign_fields [:index, :transactions, :pre_hash]
  @hash_fields [:creator, :timestamp, :signature, :proof | @sign_fields]

  @primary_key {:index, :id, autogenerate: false}
  @foreign_key_type :id

  schema "block" do
    field :pre_hash, :string
    field :proof, :integer, default: 1
    field :timestamp, :utc_datetime, default: DateTime.utc_now()
    belongs_to(:creator, Kniffel.User)
    field :hash, :string
    field :signature, :string

    has_many(:transactions, Kniffel.Blockchain.Transaction)
  end

  @doc false
  def changeset_p2p(block, attrs) do
    block
    |> cast(attrs, [:pre_hash, :transactions, :index])
    |> cast(attrs, [:proof, :timestamp, :creator, :hash, :signature])
    |> put_assoc(:transactions, attrs["transactions"] || block.transactions)
    |> verify_changeset
  end

  @doc false
  def changeset_create(block, attrs) do
    block
    |> cast(attrs, [:pre_hash, :transactions, :index])
    |> put_assoc(:transactions, attrs["transactions"] || block.transactions)
    |> sign_changeset()
    |> hash_changeset
  end

  @doc "Build a new block for given transactions and previous hash"
  def new(transactions, pre_hash, index) do
    changeset_create(
      %Block{},
      %{
        transactions: transactions,
        pre_hash: pre_hash,
        index: index
      }
    )
  end

  def genesis do
    changeset_create(
      %Block{},
      %{
        transactions: [],
        pre_hash: "ZERO_HASH",
        index: 0
      }
    )
  end

  def valid?(%Block{} = block) do
    Crypto.hash(block) == block.hash
  end

  def valid?(%Block{} = block, %Block{} = pre_block) do
    block.pre_hash == pre_block.hash && valid?(block)
  end

  def sign_changeset(%Ecto.Changeset{} = changeset) do
    private_key = Crypto.private_key(System.get_env("PRIV_KEY_PATH"))

    signature =
      changeset
      |> take(@sign_fields)
      |> Crypto.sign(private_key)

    changeset
    |> put_change(:signature, signature)
    |> put_change(:creator, Crypto.public_key(private_key))
  end

  @doc "Calculate and put the hash in the block"
  def hash_changeset(%Ecto.Changeset{} = changeset) do
    correct_hash = consensus_changeset(changeset)

    put_change(changeset, :hash, correct_hash)
  end

  def consensus_changeset(%Ecto.Changeset{} = changeset) do
    poc_changeset("", changeset)
  end

  def poc_changeset(correct_hash = "0000" <> _, _) do
    correct_hash
  end

  def poc_changeset(wrong_hash, %Ecto.Changeset{} = changeset) do
    proof = fetch_field(changeset, :proof) + 1

    changeset
    |> put_change(:proof, proof)
    |> put_change(:timestamp, DateTime.utc_now())
    |> take(@hash_fields)
    |> Crypto.hash()
    |> poc_changeset(changeset)
  end

  @doc "Verify a block using the public key present in it"
  def verify_changeset(%Ecto.Changeset{} = changeset) do
    signature = fetch_field(changeset, :signature)
    creator = fetch_field(changeset, :creator)

    case Crypto.verify(signature, creator, take(changeset, @sign_fields)) do
      :ok ->
        changeset

      :invalid ->
        add_error(changeset, :hash, "invalid",
          additional: "hash is not valid for the other fields"
        )
    end
  end

  @doc "Verify a block using the public key present in it"
  def verify_block(%Block{} = block) do
    Crypto.verify(block.signature, block.creator, Map.take(block, @sign_fields))
  end

  defp take(%Ecto.Changeset{} = changeset, fields) do
    Enum.map(fields, fn field ->
      {field, fetch_field(changeset, field)}
    end)
  end

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
