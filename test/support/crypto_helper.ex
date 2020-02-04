defmodule Kniffel.CryptoHelper do
  def create_rsa_key() do
    {:ok, private_key} = ExPublicKey.generate_key(4096)
    {:ok, public_key} = ExPublicKey.public_key_from_private_key(private_key)
    {:ok, private_pem_string} = ExPublicKey.pem_encode(private_key)
    {:ok, public_pem_string} = ExPublicKey.pem_encode(public_key)
    id = ExPublicKey.RSAPublicKey.get_fingerprint(public_key)

    %{
      id: id,
      private_key: private_key,
      public_key: public_key,
      private_pem_string: private_pem_string,
      public_pem_string: public_pem_string
    }
  end
end
