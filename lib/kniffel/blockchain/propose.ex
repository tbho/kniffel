defmodule Kniffel.Blockchain.Block.Propose do
  alias Kniffel.Blockchain.{Block, Crypto, Block.Propose}
  alias Kniffel.{Blockchain, Server}

  @crypto_fields [:block_index, :pre_hash, :transactions, :server_id, :timestamp]

  defstruct block_index: 0,
            pre_hash: '',
            transactions: [],
            server_id: '',
            timestamp: DateTime.to_string(DateTime.truncate(DateTime.utc_now(), :second)),
            signature: ''

  def change(propose \\ %Propose{}, attrs)

  def change(
        %Propose{} = propose,
        %{block: _block, transactions: _transactions, server: _server} = attrs
      ) do
    propose
    |> change_attribute(attrs, :transactions)
    |> change_attribute(attrs, :block)
    |> change_attribute(attrs, :server)
    |> change_attribute(attrs, :signature)
  end

  def change(
        %Propose{} = propose,
        %{
          "block_index" => block_index,
          "pre_hash" => pre_hash,
          "transactions" => transactions,
          "server_id" => server_id,
          "timestamp" => timestamp,
          "signature" => signature
        }
      ) do
    %{
      propose
      | block_index: block_index,
        pre_hash: pre_hash,
        transactions:
          Enum.map(transactions, &(&1 |> Map.new(fn {k, v} -> {String.to_atom(k), v} end))),
        server_id: server_id,
        timestamp: timestamp,
        signature: signature
    }
  end

  defp change_attribute(%Propose{} = propose, attrs, :transactions) do
    if length(attrs[:transactions]) > 0 do
      transactions =
        Enum.map(attrs.transactions, fn transaction ->
          %{
            id: transaction.id,
            signature: transaction.signature,
            timestamp: DateTime.to_string(transaction.timestamp)
          }
        end)

      %{propose | transactions: transactions}
    else
      propose
    end
  end

  defp change_attribute(%Propose{} = propose, %{block: %Block{} = block}, :block) do
    %{propose | block_index: block.index + 1, pre_hash: block.hash}
  end

  defp change_attribute(%Propose{} = propose, _attrs, :block), do: propose

  defp change_attribute(%Propose{} = propose, %{server: %Server{} = server}, :server) do
    %{propose | server_id: server.id}
  end

  defp change_attribute(%Propose{} = propose, _attrs, :server), do: propose

  defp change_attribute(%Propose{} = propose, _attrs, :signature) do
    with {:ok, private_key} <- Crypto.private_key(),
         {:ok, private_key_pem} <- ExPublicKey.pem_encode(private_key) do
      signature =
        Map.take(propose, @crypto_fields)
        |> Poison.encode!()
        |> Crypto.sign(private_key_pem)

      %{propose | signature: signature}
    end
  end

  def hash(%Propose{} = propose) do
    Map.take(propose, @crypto_fields)
    |> Poison.encode!()
    |> Crypto.hash()
  end

  def verify(%Propose{} = propose) do
    with {:server, %Server{} = server} <- {:server, Server.get_server(propose.server_id)},
         {:block, %Block{} = last_block} <- {:block, Blockchain.get_last_block()},
         true <- last_block.index == propose.block_index - 1,
         data <- Map.take(propose, @crypto_fields),
         data_enc <- Poison.encode!(data),
         :ok <- Crypto.verify(data_enc, server.public_key, propose.signature) do
      {:ok, propose}
    else
      {:server, nil} ->
        {:error, :server_unknown}

      false ->
        {:error, :block_index_not_correct}

      :invalid ->
        {:error, :signature_invalid}
    end
  end
end
