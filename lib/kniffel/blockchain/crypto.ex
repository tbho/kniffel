defmodule Kniffel.Blockchain.Crypto do
  alias Kniffel.Blockchain.Block

  @doc "Calculate hash of block"
  def hash(data) do
    data
    |> sha256
  end

  @doc "Sign block data using a private key"
  def sign(data, private_key) do
    with {:ok, private_key} <- ExPublicKey.loads(private_key),
         {:ok, signature} <- ExPublicKey.sign(data, private_key) do
      encode(signature)
    end
  end

  @doc "Verify a block using the public key present in it"
  def verify(signature, key, data) do
    sign = decode(signature)
    public_key = decode(key)

    {:ok, valid} =
      data
      |> Poison.encode!()
      |> ExPublicKey.verify(sign, public_key)

    if valid,
      do: :ok,
      else: :invalid
  end

  def private_key() do
    System.get_env("PRIV_KEY_PATH")
    |> ExPublicKey.load()
  end

  # Calculate SHA256 for a binary string
  defp sha256(binary) do
    :crypto.hash(:sha256, binary) |> encode
  end

  def encode(binary), do: Base.encode16(binary)
  def decode(binary), do: Base.decode16!(binary)
end
