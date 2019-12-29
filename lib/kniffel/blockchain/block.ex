defmodule Kniffel.Blockchain.Block do
  alias Kniffel.Server
  alias Kniffel.Blockchain.Crypto
  alias Kniffel.Blockchain.Block

  use Ecto.Schema
  import Ecto.Changeset

  # Specify which fields to hash in a block
  @sign_fields [:index, :data, :pre_hash]
  @hash_fields [:server_id, :timestamp, :signature, :proof | @sign_fields]

  @primary_key {:index, :id, autogenerate: false}
  @foreign_key_type :id

  schema "block" do
    field :pre_hash, :string
    field :proof, :integer, default: 1
    field :timestamp, :string, default: Timex.now() |> Timex.format!("{ISO:Extended}")
    field :hash, :string
    field :signature, :string
    field :data, :string

    belongs_to(:server, Kniffel.Server, type: :string)
    has_many(:transactions, Kniffel.Blockchain.Transaction)
  end

  @doc false
  def changeset_p2p(block, attrs) do
    block
    |> cast(attrs, [:pre_hash, :data, :index])
    |> cast(attrs, [:proof, :timestamp, :hash, :signature, :server_id])
    |> put_assoc(:transactions, attrs["transactions"] || block.transactions)
    |> put_assoc(:server, attrs["server"] || block.server)
    |> verify_changeset
  end

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
         server_id <- ExPublicKey.RSAPublicKey.get_fingerprint(rsa_pub_key) do
      changeset =
        changeset
        |> cast(%{server_id: server_id}, [:server_id])

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

  def pow_changeset(_, %Ecto.Changeset{} = changeset) do
    {_, proof} = fetch_field(changeset, :proof)

    changeset =
      changeset
      |> put_change(:proof, proof + 1)
      |> put_change(:timestamp, Timex.now() |> Timex.format!("{ISO:Extended}"))

    changeset
    |> take(@hash_fields)
    |> Poison.encode!()
    |> Crypto.hash()
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

  @doc "Verify a block using the public key present in it"
  def verify_changeset(%Ecto.Changeset{} = changeset) do
    with {_, signature} = fetch_field(changeset, :signature),
         {_, hash} = fetch_field(changeset, :hash),
         {_, server} <- fetch_field(changeset, :server),
         %Server{} = server <- Server.get_server(server.id) do
      data =
        changeset
        |> take(@sign_fields)
        |> Poison.encode!()

      calculated_hash =
        changeset
        |> take(@hash_fields)
        |> Poison.encode!()
        |> Crypto.hash()

      changeset =
        if hash != calculated_hash do
          add_error(changeset, :hash, "invalid",
            additional: "hash is not valid for the other fields"
          )
        else
          changeset
        end

      case Crypto.verify(data, server.public_key, signature) do
        :ok ->
          changeset

        :invalid ->
          add_error(changeset, :signature, "invalid",
            additional: "signature is not valid for the other fields"
          )
      end
    end
  end

  def json(%Kniffel.Blockchain.Block{} = block) do
    %{
      index: block.index,
      pre_hash: block.pre_hash,
      proof: block.proof,
      data: Poison.decode!(block.data),
      # data: %{"transactions" => transaction_data},
      hash: block.hash,
      signature: block.signature,
      timestamp: block.timestamp,
      server_id: block.server_id
    }
  end

  def json_encode(%Kniffel.Blockchain.Block{} = block) do
    %{
      index: block.index,
      pre_hash: block.pre_hash,
      proof: block.proof,
      data: block.data,
      hash: block.hash,
      signature: block.signature,
      timestamp: block.timestamp,
      server_id: block.server_id
    }
  end
end
