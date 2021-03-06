defmodule Kniffel.Blockchain.Block.ProposeResponse do
  alias Kniffel.Blockchain.{Crypto, Block, Block.Propose, Block.ProposeResponse}
  alias Kniffel.{Server}

  @crypto Application.get_env(:kniffel, :crypto)

  defstruct hash: '',
            server_id: '',
            signature: '',
            error: :none

  def change(propose_response \\ %ProposeResponse{}, attrs)

  def change(
        %ProposeResponse{} = propose_response,
        %{server: _server, propose: _propose} = attrs
      ) do
    propose_response
    |> change_attribute(attrs, :server)
    |> change_attribute(attrs, :propose)
    |> change_attribute(attrs, :signature)
  end

  def change(
        %ProposeResponse{} = propose_response,
        %{
          server: _server,
          error: error
        } = attrs
      ) do
    %{propose_response | error: error}
    |> change_attribute(attrs, :server)
    |> change_attribute(attrs, :signature)
  end

  def change(
        %ProposeResponse{} = propose_response,
        %{
          "hash" => hash,
          "server_id" => server_id,
          "error" => error,
          "signature" => signature
        }
      ) do
    %{
      propose_response
      | hash: hash,
        server_id: server_id,
        error: String.to_atom(error),
        signature: signature
    }
  end

  defp change_attribute(
         %ProposeResponse{} = propose_response,
         %{propose: %Propose{} = propose},
         :propose
       ) do
    %{propose_response | hash: Propose.hash(propose)}
  end

  defp change_attribute(%ProposeResponse{} = propose_response, _attrs, :propose),
    do: propose_response

  defp change_attribute(
         %ProposeResponse{} = propose_response,
         %{server: %Server{} = server},
         :server
       ) do
    %{propose_response | server_id: server.id}
  end

  defp change_attribute(%ProposeResponse{} = propose_response, _attrs, :server),
    do: propose_response

  defp change_attribute(%ProposeResponse{} = propose_response, _attrs, :signature) do
    with {:ok, private_key} <- @crypto.private_key(),
         {:ok, private_key_pem} <- ExPublicKey.pem_encode(private_key) do
      signature =
        %{hash: propose_response.hash, error: propose_response.error}
        |> Poison.encode!()
        |> Crypto.sign(private_key_pem)

      %{propose_response | signature: signature}
    end
  end

  def verify(%Propose{} = propose, %ProposeResponse{error: :none} = propose_response),
    do: verify_signature(propose_response, Propose.hash(propose))

  def verify(%Block{} = block, %ProposeResponse{error: :none} = propose_response),
    do: verify_signature(propose_response, block.hash)

  def verify(_propose_or_block, %ProposeResponse{error: error}), do: {:error, error}

  defp verify_signature(propose_response, hash) do
    with %Server{} = server <- Server.get_server(propose_response.server_id),
         true <- propose_response.hash == hash,
         data_enc <-
           Poison.encode!(%{hash: propose_response.hash, error: propose_response.error}),
         :ok <- Crypto.verify(data_enc, server.public_key, propose_response.signature) do
      propose_response
    else
      nil ->
        {:error, :server_unknown}

      false ->
        {:error, :hash_not_correct}

      :invalid ->
        {:error, :signature_invalid}
    end
  end

  def json(%ProposeResponse{} = propose_response) do
    %{
      hash: propose_response.hash,
      server_id: propose_response.server_id,
      error: propose_response.error,
      signature: propose_response.signature
    }
  end
end
