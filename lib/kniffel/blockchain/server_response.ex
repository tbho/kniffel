defmodule Kniffel.Blockchain.Block.ServerResponse do
  alias Kniffel.Blockchain.{Crypto, Block, Block.Propose, Block.ServerResponse}
  alias Kniffel.{Server}

  defstruct hash: '',
            server_id: '',
            signature: '',
            error: :none

  def change(server_response \\ %ServerResponse{}, attrs)

  def change(
        %ServerResponse{} = server_response,
        %{server: _server, propose: _propose} = attrs
      ) do
    server_response
    |> change_attribute(attrs, :server)
    |> change_attribute(attrs, :propose)
    |> change_attribute(attrs, :signature)
  end

  def change(
        %ServerResponse{} = server_response,
        %{server: _server, block: _block} = attrs
      ) do
    server_response
    |> change_attribute(attrs, :server)
    |> change_attribute(attrs, :block)
    |> change_attribute(attrs, :signature)
  end

  def change(
        %ServerResponse{} = server_response,
        %{
          server: _server,
          error: error
        } = attrs
      ) do
    %{server_response | error: error}
    |> change_attribute(attrs, :server)
    |> change_attribute(attrs, :signature)
  end

  def change(
        %ServerResponse{} = server_response,
        %{
          "hash" => hash,
          "server_id" => server_id,
          "error" => error,
          "signature" => signature
        }
      ) do
    %{
      server_response
      | hash: hash,
        server_id: server_id,
        error: String.to_atom(error),
        signature: signature
    }
  end

  defp change_attribute(
         %ServerResponse{} = server_response,
         %{propose: %Propose{} = propose},
         :propose
       ) do
    %{server_response | hash: Propose.hash(propose)}
  end

  defp change_attribute(%ServerResponse{} = server_response, _attrs, :propose),
    do: server_response

  defp change_attribute(
         %ServerResponse{} = server_response,
         %{block: %Block{} = block},
         :block
       ) do
    %{server_response | hash: block.hash}
  end

  defp change_attribute(%ServerResponse{} = server_response, _attrs, :block),
    do: server_response

  defp change_attribute(
         %ServerResponse{} = server_response,
         %{server: %Server{} = server},
         :server
       ) do
    %{server_response | server_id: server.id}
  end

  defp change_attribute(%ServerResponse{} = server_response, _attrs, :server),
    do: server_response

  defp change_attribute(%ServerResponse{} = server_response, _attrs, :signature) do
    with {:ok, private_key} <- Crypto.private_key(),
         {:ok, private_key_pem} <- ExPublicKey.pem_encode(private_key) do
      signature =
        %{hash: server_response.hash, error: server_response.error}
        |> Poison.encode!()
        |> Crypto.sign(private_key_pem)

      %{server_response | signature: signature}
    end
  end

  def verify(%Propose{} = propose, %ServerResponse{error: :none} = server_response),
    do: verify_signature(server_response, Propose.hash(propose))

  def verify(%Block{} = block, %ServerResponse{error: :none} = server_response),
    do: verify_signature(server_response, block.hash)

  def verify(_propose_or_block, %ServerResponse{error: error}), do: {:error, error}

  defp verify_signature(server_response, hash) do
    with %Server{} = server <- Server.get_server(server_response.server_id),
         true <- server_response.hash == hash,
         data_enc <-
           Poison.encode!(%{hash: server_response.hash, error: server_response.error}),
         :ok <- Crypto.verify(data_enc, server.public_key, server_response.signature) do
      server_response
    else
      nil ->
        {:error, :server_unknown}

      false ->
        {:error, :hash_not_correct}

      :invalid ->
        {:error, :signature_invalid}
    end
  end

  def json(%ServerResponse{} = server_response) do
    %{
      hash: server_response.hash,
      server_id: server_response.server_id,
      error: server_response.error,
      signature: server_response.signature
    }
  end
end
