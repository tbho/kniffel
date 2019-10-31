defmodule Kniffel.Blockchain.Block do
  alias Kniffel.Blockchain.Crypto
  alias Kniffel.Blockchain.Block

  defstruct index: 0,
            pre_hash: "",
            proof: 1,
            timestamp: DateTime.utc_now(),
            data: [],
            creator: "",
            hash: "",
            signature: ""

  @doc "Build a new block for given data and previous hash"
  def new(data, pre_hash, index) do
    %Block{
      data: data,
      pre_hash: pre_hash,
      index: index
    }
  end

  def genesis do
    %Block{
      data: [],
      pre_hash: "ZERO_HASH"
    }
  end

  def valid?(%Block{} = block) do
    Crypto.hash(block) == block.hash
  end

  def valid?(%Block{} = block, %Block{} = pre_block) do
    block.pre_hash == pre_block.hash && valid?(block)
  end
end
