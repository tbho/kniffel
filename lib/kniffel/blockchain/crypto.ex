defmodule Kniffel.Blockchain.Crypto do
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
  def verify(data, public_key_pem, signature) do
    with {:ok, public_key} <- ExPublicKey.loads(public_key_pem) do
      sign = decode(signature)

      {:ok, valid} = ExPublicKey.verify(data, sign, public_key)

      if valid,
        do: :ok,
        else: :invalid
    end
  end

  @callback private_key() :: {:ok, ExPublicKey.RSAPrivateKey.t()} | {:error, Atom.t()}
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
