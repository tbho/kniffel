defmodule Kniffel.Blockchain.Crypto do
  alias Kniffel.Blockchain.Block

  # Specify which fields to hash in a block
  @sign_fields [:index, :data, :timestamp, :pre_hash]
  @hash_fields [:creator, :signature, :proof | @sign_fields]

  @doc "Calculate hash of block"
  def hash(%{} = block) do
    block
    |> Map.take(@hash_fields)
    |> Poison.encode!()
    |> sha256
  end

  @doc "Calculate and put the hash in the block"
  def hash!(%Block{} = block) do
    correct_hash = poc("", block)
    %{block | hash: correct_hash}
  end

  def poc(correct_hash = "0000" <> _, _) do
    correct_hash
  end

  def poc(wrong_hash, %{proof: proof}= block) do
    block = %{block | proof: proof + 1}
    block
    |> hash()
    |> poc(block)
  end

  @doc "Sign block data using a private key"
  def sign(block, private_key) do
    block
    |> Map.take(@sign_fields)
    |> Poison.encode!()
    |> ExPublicKey.sign(private_key)
    |> IO.inspect
    |> elem(1)
    |> encode
  end

  def sign!(block, private_key) do
    block
    |> Map.put(:creator, public_key(private_key))
    |> Map.put(:signature, sign(block, private_key))
  end

  @doc "Verify a block using the public key present in it"
  def verify(block) do
    sign = decode(block.signature)
    key = decode(block.creator)

    {:ok, valid} =
      block
      |> Poison.encode(@sign_fields)
      |> ExPublicKey.verify(sign, key)

    if valid,
      do: :ok,
      else: :invalid
  end


  # Calculate SHA256 for a binary string
  defp sha256(binary) do
    :crypto.hash(:sha256, binary) |> encode
  end


  def public_key(private_key) do
    private_key
    |> ExPublicKey.public_key_from_private_key()
    |> elem(1)
    |> encode
  end

  def private_key(path) do
    path
    |> ExPublicKey.load()
    |> elem(1)
  end

  def encode(binary), do: Base.encode16(binary)
  def decode(binary), do: Base.decode16!(binary)
end
