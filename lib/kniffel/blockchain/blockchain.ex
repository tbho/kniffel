defmodule Kniffel.Blockchain do
  @moduledoc """
  Blockchain Module to controll and insert data into it.
  """

  import Ecto.Query, warn: false

  alias Kniffel.Repo

  alias Kniffel.Blockchain.{
    Block,
    Block.Propose,
    Block.ProposeResponse,
    Transaction
  }

  alias Kniffel.{Game, Game.Score, User, Server}
  alias Kniffel.Scheduler.{RoundSpecification, ServerAge}

  require Logger

  @http_client Application.get_env(:kniffel, :request)
  @round_endpoint Application.get_env(:kniffel, :round_endpoint)

  # -----------------------------------------------------------------
  # -- Block
  # -----------------------------------------------------------------
  def get_blocks() do
    Block
    |> order_by(desc: :index)
    |> Repo.all()
  end

  def get_block(index) do
    Block
    |> Repo.get(index)
  end

  def genesis() do
    block_params = %{
      data:
        Poison.encode!(%{
          "propose" => nil,
          "propose_response" => [],
          "transactions" => []
        }),
      pre_hash: "ZERO_HASH",
      index: 0,
      transactions: []
    }

    %Block{}
    |> Repo.preload([:server])
    |> Block.changeset_create(block_params)
    |> Repo.insert()
  end

  def get_last_block() do
    Block
    |> order_by(desc: :index)
    |> limit(1)
    |> Repo.one()
  end

  def get_block_data_ids() do
    get_block_data_query()
    |> select([t], t.id)
    |> Repo.all()
  end

  def get_block_data() do
    get_block_data_query()
    |> Repo.all()
  end

  defp get_block_data_query() do
    limit = Application.get_env(:kniffel, :block_transaction_limit)

    Transaction
    |> where([t], is_nil(t.block_index))
    |> order_by(asc: :timestamp)
    |> limit(^limit)
  end

  def propose_new_block() do
    block_data = get_block_data()

    if length(block_data) > 0 do
      propose =
        Map.new()
        |> Map.put(:transactions, block_data)
        |> Map.put(:block, get_last_block())
        |> Map.put(:server, Server.get_this_server())
        |> Propose.change()

      Kniffel.Cache.delete({:propose, block_index: propose.block_index})
      Kniffel.Cache.delete({:propose_response, block_index: propose.block_index})

      Kniffel.Cache.set({:propose, block_index: propose.block_index}, propose)

      Server.get_authorized_servers(false)
      |> Enum.map(fn server ->
        @round_endpoint.propose_to_server(server, propose)
      end)

      {:ok, propose}
    else
      {:error, :no_transactions}
    end
  end

  @callback propose_to_server(server :: Server.t(), propose :: Propose.t()) ::
              ProposeResponse.t() | {:error, String.t()} | {:error, Atom.t()}
  def propose_to_server(server, propose) do
    {:ok, %{"propose_response" => propose_response}} =
      @http_client.post(
        server.url <> "/api/blocks/propose",
        %{
          propose: propose,
          round_specification:
            RoundSpecification.json(RoundSpecification.get_round_specification())
        }
      )

    with %ProposeResponse{} = propose_response <- ProposeResponse.change(propose_response),
         %ProposeResponse{} = propose_response <-
           ProposeResponse.verify(propose, propose_response),
         true <- propose_response.server_id == server.id do
      propose_response

      results = Kniffel.Cache.get({:propose_response, block_index: propose.block_index}) || []

      Kniffel.Cache.set(
        {:propose_response, block_index: propose.block_index},
        [propose_response] ++ results
      )

      propose_response
    else
      {:error, message} ->
        Logger.debug(message)
        {:error, message}

      false ->
        {:error, :server_id_does_not_match}
    end
  end

  def validate_block_proposal(%Propose{} = propose) do
    with {:ok, propose} <- Propose.verify(propose),
         transactions <- get_proposal_transactions(propose),
         {:transactions, false} <- {:transactions, Enum.empty?(transactions)},
         block_data_ids <- get_block_data_ids(),
         true <- Enum.all?(transactions, &(&1.id in block_data_ids)) do
      propose_response =
        Map.new()
        |> Map.put(:propose, propose)
        |> Map.put(:server, Server.get_this_server())
        |> ProposeResponse.change()

      propose_response
    else
      {:transactions, true} ->
        Map.new()
        |> Map.put(:error, :no_transactions_in_block)
        |> Map.put(:server, Server.get_this_server())
        |> ProposeResponse.change()

      {:error, message} ->
        Map.new()
        |> Map.put(:error, message)
        |> Map.put(:server, Server.get_this_server())
        |> ProposeResponse.change()

      false ->
        Map.new()
        |> Map.put(:error, :oldest_transaction_are_not_in_block)
        |> Map.put(:server, Server.get_this_server())
        |> ProposeResponse.change()
    end
  end

  def get_proposal_transactions(%Propose{} = propose) do
    server = Server.get_server(propose.server_id)

    Enum.map(propose.transactions, fn propose_transaction ->
      %Transaction{} =
        transaction =
        case get_transaction(propose_transaction.id) do
          %Transaction{} = transaction ->
            transaction

          nil ->
            get_transaction_from_server(propose_transaction.id, server.url)
        end

      true = transaction.signature == propose_transaction.signature
      true = transaction.timestamp == propose_transaction.timestamp

      transaction
    end)
    |> Enum.sort(&(&1.timestamp < &2.timestamp))
  end

  def commit_new_block() do
    last_block = get_last_block()

    propose = Kniffel.Cache.take({:propose, block_index: last_block.index + 1})

    propose_response = Kniffel.Cache.take({:propose_response, block_index: last_block.index + 1})

    if !is_nil(propose) && !is_nil(propose_response) do
      true = propose.pre_hash == last_block.hash
      true = propose.block_index == last_block.index + 1
      true = propose.server_id == Server.get_this_server().id

      propose_response_count =
        Enum.filter(propose_response, &(&1.error == :none)) ||
          []
          |> length

      true = propose_response_count >= calculate_min_propose_response_count()

      transactions = get_block_data()

      true =
        Enum.map(transactions, & &1.id) |> Enum.sort() ==
          Enum.map(propose.transactions, & &1.id) |> Enum.sort()

      transaction_data =
        Enum.map(transactions, fn transaction ->
          Map.take(transaction, [:id, :signature, :timestamp, :server_id, :game_id, :data])
        end)

      data =
        Poison.encode!(%{
          "propose" => propose,
          "propose_response" => propose_response,
          "transactions" => transaction_data
        })

      block_params = %{
        data: data,
        transactions: transactions,
        index: last_block.index + 1,
        pre_hash: last_block.hash
      }

      {:ok, block} =
        %Block{}
        |> Repo.preload([:server])
        |> Block.changeset_create(block_params)
        |> Repo.insert()

      Kniffel.Cache.delete({:block, block_index: block.index})
      Kniffel.Cache.delete({:block_response, block_index: block.index})

      Kniffel.Cache.set({:block, block_index: block.index}, block)

      Server.get_authorized_servers(false)
      |> Enum.map(fn server ->
        @round_endpoint.commit_to_server(server, block)
      end)

      {:ok, block}
    else
      {:error, :no_propose_for_block}
    end
  end

  @callback commit_to_server(server :: Server.t(), block :: Block.t()) ::
              {:ok, String.t()} | {:error, String.t()} | {:error, Atom.t()}
  def commit_to_server(server, block) do
    with {:ok, %{"ok" => message}} <-
           @http_client.post(
             server.url <> "/api/blocks/commit",
             %{
               block: Block.json_encode(block),
               round_specification:
                 RoundSpecification.json(RoundSpecification.get_round_specification())
             }
           ) do
      {:ok, message}
    else
      {:error, message} ->
        {:error, message}
    end
  end

  def validate_and_insert_block(
        %{"server_id" => server_id, "data" => data, "index" => index} = block_params
      ) do
    with %{
           "propose" => propose,
           "propose_response" => propose_responses,
           "transactions" => transaction_data
         } <-
           Poison.decode!(data),
         %Server{authority: true} = server <- Server.get_server(server_id),
         %Propose{} = propose <- Propose.change(propose),
         nil <- get_block(index) do
      transactions =
        Enum.map(transaction_data, fn transaction_params ->
          transaction = get_transaction(transaction_params["id"])

          case transaction do
            %Transaction{} = transaction ->
              if transaction.signature == transaction_params["signature"] do
                transaction
              else
                {:transaction_signature, "already known transaction does not match signature"}
              end

            nil ->
              {:ok, %{body: %{transaction: transaction_params}}} =
                HTTPoison.get(server.url <> "/api/transactions/#{transaction_params["id"]}")

              {:ok, transaction} = insert_transaction(transaction_params, server.url)
              transaction
          end
        end)

      true =
        Enum.map(transactions, & &1.id) |> Enum.sort() ==
          Enum.map(propose.transactions, & &1.id) |> Enum.sort()

      true = propose.pre_hash == block_params["pre_hash"]
      true = propose.block_index == block_params["index"]
      true = propose.server_id == server.id

      propose_response_count =
        Enum.map(propose_responses, fn propose_response_params ->
          propose_response =
            propose_response_params
            |> ProposeResponse.change()

          %ProposeResponse{} = ProposeResponse.verify(propose, propose_response)
        end)
        |> Enum.count(&(%ProposeResponse{} = &1))

      with true <- propose_response_count >= calculate_min_propose_response_count(),
           block_params <-
             block_params
             |> Map.drop(["transactions"])
             |> Map.put("server", server)
             |> Map.put("transactions", transactions),
           {:ok, _block} <-
             %Block{}
             |> Repo.preload([:server, :transactions])
             |> Block.changeset_p2p(block_params)
             |> Repo.insert() do
        %{ok: :accept}
      else
        false ->
          %{error: :not_enough_approvals}
      end
    else
      %Block{} = _block ->
        %{error: :index_blocked}

      nil ->
        %{error: :unknown_server}
    end
  end

  def finalize_block() do
    last_block = get_last_block()

    block = Kniffel.Cache.take({:block, block_index: last_block.index})

    round_specification =
      RoundSpecification.json(RoundSpecification.get_next_round_specification())

    server_age = ServerAge.json(ServerAge.update_server_ages(ServerAge.get_server_age()))
    this_server = Server.get_this_server()

    Server.get_authorized_servers(false)
    |> Enum.map(fn server ->
      @round_endpoint.finalize_to_server(
        block,
        server,
        this_server,
        round_specification,
        server_age
      )
    end)

    :ok
  end

  @callback finalize_to_server(
              Block.t(),
              Server.t(),
              Server.t(),
              RoundSpecification.t(),
              ServerAge.t()
            ) ::
              :ok | {:error, String.t()} | {:error, Atom.t()}
  def finalize_to_server(block, server, this_server, round_specification, server_age) do
    with {:ok, %{"ok" => "accept"}} <-
           @http_client.post(
             server.url <> "/api/blocks/finalize",
             %{
               block_height: %{
                 index: block.index,
                 timestamp: block.timestamp,
                 server_id: this_server.id,
                 hash: block.hash
               },
               round_specification: round_specification,
               server_age: server_age
             }
           ) do
      :ok
    else
      {:error, error} ->
        {:error, error}
    end
  end

  def handle_height_change(%{
        "server_id" => server_id,
        "hash" => hash,
        "index" => index
      }) do
    with %Server{authority: true} = server <- Server.get_server(server_id),
         {:leader, true} <- {:leader, ServerAge.is_leader?(server.id)},
         {:block, %Block{} = last_block} = {:block, get_last_block()},
         true = index == last_block.index,
         true = hash == last_block.hash do
      # TODO: spread block to slave nodes
      {:ok, :accept}
    else
      # --- Server.get_server(server_id) ---------------
      %Server{} = _server ->
        {:error, :no_master_node}

      nil ->
        {:error, :unknown_server}

      # --- is_leader(server) --------------------------
      {:leader, false} ->
        {:error, :server_is_not_leader}

      # --- get_last_block -----------------------------
      {:block, _} ->
        {:error, :could_not_request_last_block}

      # --- index and hash comparison ------------------
      false ->
        %Block{} = block = compare_block_height_with_network()

        if index == block.index and hash == block.hash do
          {:ok, :accept}
        else
          {:ok, :blocks_do_not_match}
        end
    end
  end

  @doc """
    This function is called if at finalize_block step the blocks in network don't
    match. Function will compare heights in network and choose the height which
    appears most. If all answers differ, block with highest index and oldest
    timestamp is choosen and inserted or spread to network.
  """
  def compare_block_height_with_network() do
    block_height_responses = get_heigt_from_network()
    # if no server is in network empty list is returned
    # otherwise answers will be grouped and answer with highest count is choosen
    # if all respones are unique the block height with highest index and oldest timestamp is choosen
    with false <- Enum.empty?(block_height_responses),
         uniq_block_heights <- Enum.uniq(block_height_responses),
         grouped_block_height <-
           Enum.map(uniq_block_heights, fn uniq_block_height ->
             {uniq_block_height, Enum.count(block_height_responses, &(uniq_block_height == &1))}
           end) do
      # test if all answers are unique (have a count of 1)

      if Enum.all?(grouped_block_height, &(elem(&1, 1) == 1)) do
        # ---------------------------
        # -- all responses are unique
        # ---------------------------
        IO.inspect("-- all responses are unique")

        # get block with highest index and oldest timestamp from responses
        block_height = get_highest_and_oldest_block_height(block_height_responses)

        # get last block from this node
        %Block{} = last_block = Kniffel.Blockchain.get_last_block()

        # compare last block from this server to block with highest index and oldest timestamp from network
        with {:index, true} <- {:index, last_block.index == block_height["index"]},
             {:hash, true} <- {:hash, last_block.hash == block_height["hash"]} do
          IO.inspect("blocks match")
          :ok
        else
          {:index, false} ->
            # if this index is higher, block is spread to network, otherwise block is requested
            if last_block.index > block_height["index"] do
              IO.inspect("this block index is HIGHER! than network")
              send_block_to_server(block_height["server_id"], last_block)
            else
              IO.inspect("this block index is LOWER! than network")

              request_and_insert_block_from_server(
                block_height["server_id"],
                block_height["index"]
              )
            end

          {:hash, false} ->
            # if this index is equal but hash don't match the timestamp is checked
            # if this timestamp is older, block is spread to network, otherwise block is requested
            if last_block.timestamp < block_height["timestamp"] do
              IO.inspect("this block timestamp is OLDER! than network")
              send_block_to_server(block_height["server_id"], last_block)
            else
              IO.inspect("this block timestamp is HIGHER! than network")

              request_and_insert_block_from_server(
                block_height["server_id"],
                block_height["index"]
              )
            end
        end
      else
        # ---------------------------------------
        # -- a response with a count > 1 is found
        # ---------------------------------------
        IO.inspect("-- a response with a count > 1 is found")

        # the response with the highest count is selected
        sort_block_heights = Enum.sort_by(grouped_block_height, &elem(&1, 1), &>=/2)
        {block_height, _count} = List.first(sort_block_heights)

        # and will be requested and inserted
        request_and_insert_block_from_server(block_height["server_id"], block_height["index"])
      end
    else
      true ->
        # no other master servers found, so the last block is highest
        :ok
    end
  end

  defp get_heigt_from_network() do
    servers = Server.get_authorized_servers(false)

    Enum.reduce(servers, [], fn server, result ->
      with {:ok, %{"height_response" => height_response}} <-
             @http_client.get(server.url <> "/api/blocks/height"),
           {:ok, timestamp} <- Timex.parse(height_response["timestamp"], "{ISO:Extended}") do
        result ++ [Map.put(height_response, "timestamp", timestamp)]
      else
        {:error, error} ->
          Logger.debug(inspect(error))
          result
      end
    end)
  end

  defp send_block_to_server(server_id, block) do
    server = Server.get_server(server_id)

    with {:ok, _response} <-
           @http_client.post(server.url <> "/api/blocks", %{
             block: Block.json_encode(block)
           }) do
      :ok
    else
      {:error, _message} ->
        :error
    end
  end

  defp request_and_insert_block_from_server(server_id, block_index) do
    server = Server.get_server(server_id)

    with {:ok, %{"block" => block_response}} <-
           @http_client.get(server.url <> "/api/blocks/#{block_index}"),
         {:ok, _block} <- insert_block_from_network(block_response) do
      :ok
    else
      {:error, error} ->
        Logger.debug(inspect(error))
        :error
    end
  end

  def insert_block_from_network(
        %{"server_id" => server_id, "index" => index, "hash" => hash} = block_params
      ) do
    %Block{} = last_block = get_last_block()

    with {:index, true} <- {:index, last_block.index == index},
         {:hash, true} <- {:hash, last_block.hash == hash} do
      {:ok, last_block}
    else
      {:index, false} ->
        IO.inspect("index is not right!")

        if last_block.index > index do
          IO.inspect("last_block index is higher")
          # if last_block is higher delete blocks with higher index and
          # mark all transactions as not in block
          set_transaction_ids_to_nil_for_blocks_with_higher_index(index)
          delete_block_with_higher_index(index)

          insert_block_from_network(block_params)
        else
          IO.inspect("last_block index is lower")

          with :ok <- request_and_insert_block_from_server(server_id, index - 1) do
            insert_block_network(block_params)
          else
            :error ->
              {:error, :could_not_request_block}
          end
        end

      {:hash, false} ->
        # delete last block and mark transactions as not in block
        set_transaction_ids_to_nil_for_block(index)
        delete_block(last_block)

        # insert new block
        insert_block_network(block_params)
    end
  end

  def set_transaction_ids_to_nil_for_blocks_with_higher_index(index) do
    transaction_id_query()
    |> where([t, b], b.index > ^index)
    |> update_transaction_ids()
  end

  def set_transaction_ids_to_nil_for_block(index) do
    transaction_id_query()
    |> where([t, b], b.index == ^index)
    |> update_transaction_ids()
  end

  defp transaction_id_query(), do: join(Transaction, :inner, [t], b in assoc(t, :block))
  defp update_transaction_ids(query), do: Repo.update_all(query, set: [block_index: nil])

  def delete_block(block) do
    Repo.delete(block)
  end

  def delete_block_with_higher_index(index) when not is_nil(index) do
    Block
    |> where([b], b.index > ^index)
    |> Repo.delete_all()
  end

  defp insert_block_network(%{"server_id" => server_id, "data" => data} = block_params) do
    data = Poison.decode!(data)

    server = Server.get_server(server_id)

    transactions =
      Enum.map(data["transactions"], fn transaction_params ->
        transaction =
          case get_transaction(transaction_params["id"]) do
            %Transaction{} = transaction ->
              transaction

            nil ->
              get_transaction_from_server(transaction_params["id"], server.url)
          end

        if transaction.signature == transaction_params["signature"] do
          transaction
        else
          nil
        end
      end)

    block_params =
      block_params
      |> Map.drop(["transactions"])
      |> Map.put("server", server)
      |> Map.put("transactions", transactions)

    %Block{}
    |> Repo.preload([:server, :transactions])
    |> Block.changeset_p2p(block_params)
    |> Repo.insert()
  end

  defp get_highest_and_oldest_block_height(block_height_responses) do
    sort_block_heights = Enum.sort_by(block_height_responses, & &1["index"], &>=/2)
    block_height = List.first(sort_block_heights)

    case Enum.count(block_height_responses, &(block_height["index"] == &1["index"])) do
      n when n > 1 ->
        same_height_blocks =
          Enum.filter(block_height_responses, &(&1["index"] == block_height["index"]))

        sort_same_height_blocks = Enum.sort_by(same_height_blocks, & &1["timestamp"])
        List.first(sort_same_height_blocks)

      1 ->
        block_height
    end
  end

  def get_active_servers() do
    limit = Application.get_env(:kniffel, :active_server_treshhold)

    blocks =
      Block
      |> order_by(desc: :index)
      |> limit(^limit)
      |> Repo.all()

    Enum.reduce(blocks, [], fn block, result ->
      if block.index != 0 do
        %{"propose_response" => propose_responses} = Poison.decode!(block.data)

        Enum.uniq(
          result ++ Enum.map(propose_responses, &([&1["server_id"]] ++ [block.server_id]))
        )
      else
        result ++ [block.server_id]
      end
    end)
  end

  def calculate_min_propose_response_count() do
    twothirds = length(get_active_servers()) / 3 * 2
    if twothirds < 1, do: 1, else: Kernel.trunc(twothirds)
  end

  # -----------------------------------------------------------------
  # -- Transaction
  # -----------------------------------------------------------------
  def get_transactions(filter_params) do
    query =
      from(t in Transaction)
      |> order_by(asc: :timestamp)

    query =
      Enum.reduce(filter_params, query, fn {key, value}, query ->
        case key do
          "confirmed" ->
            where(query, [t], is_nil(t.block_index) != ^value)

          "user" ->
            where(query, [t], t.user_id == ^value)
        end
      end)

    Repo.all(query)
  end

  def get_transaction(id) do
    Transaction
    |> Repo.get(id)
  end

  def get_transaction_from_server(id, server_url) do
    {:ok, %{"transaction" => transaction_params}} =
      @http_client.get(server_url <> "/api/transactions/#{id}")

    case insert_transaction(transaction_params, server_url) do
      {:ok, transaction} ->
        transaction

      {:error, message} ->
        raise message
    end
  end

  def data_for_transaction?(user_id) do
    scores =
      user_id
      |> score_query_for_transaction
      |> Repo.aggregate(:count, :id)

    games =
      user_id
      |> game_query_for_transaction
      |> Repo.aggregate(:count, :id)

    games > 0 || scores > 0
  end

  defp get_transaction_data(user_id) do
    scores =
      user_id
      |> score_query_for_transaction
      |> Repo.all()

    games =
      user_id
      |> game_query_for_transaction
      |> Repo.all()

    {games, scores}
  end

  defp score_query_for_transaction(user_id) do
    Score
    |> where([s], is_nil(s.transaction_id))
    |> where([s], s.user_id == ^user_id)
    |> where([s], s.score_type != "none")
    |> order_by(asc: :id)
  end

  defp game_query_for_transaction(user_id) do
    Game
    |> preload(:users)
    |> where([g], is_nil(g.transaction_id))
    |> where([g], g.user_id == ^user_id)
  end

  def create_transaction(transaction_params, user) do
    {games, scores} = get_transaction_data(user.id)

    if length(games) > 0 || length(scores) > 0 do
      score_data =
        Enum.map(scores, fn score ->
          Map.take(score, [
            :dices,
            :score_type,
            :id,
            :predecessor_id,
            :user_id,
            :game_id,
            :inserted_at,
            :signature,
            :server_id
          ])
        end)

      game_data =
        Enum.map(games, fn game ->
          users =
            Enum.map(game.users, fn user ->
              Map.get(user, :id)
            end)

          Map.take(game, [:user_id, :inserted_at, :id])
          |> Map.put(:users, users)
        end)

      data = Poison.encode!(%{"scores" => score_data, "games" => game_data})

      transaction_params =
        transaction_params
        |> Map.drop(["user"])
        |> Map.put("user", user)
        |> Map.put("data", data)
        |> Map.put("games", games)
        |> Map.put("scores", scores)

      %Transaction{}
      |> Repo.preload([:user, :block])
      |> Transaction.changeset_create(transaction_params)
      |> Repo.insert()
    else
      {:error, :no_data_for_transaction}
    end
  end

  def send_transaction_to_server(transaction) do
    this_server = Server.get_this_server()
    servers = Server.get_servers(false)

    Enum.map(servers, fn server ->
      @http_client.post(
        server.url <> "/api/transactions",
        %{
          transaction: Transaction.json_encode(transaction),
          server: %{url: this_server.url}
        }
      )
    end)

    {:ok, transaction}
  end

  def request_not_confirmed_transactions_from_network() do
    try do
      servers = Server.get_authorized_servers(false)

      Enum.reduce(servers, [], fn server, result ->
        result ++ request_not_confirmed_transactions_from_network(server.url)
      end)

      :ok
    rescue
      e in RuntimeError ->
        Logger.error(e.message)
        :error
    end
  end

  def request_not_confirmed_transactions_from_network(server_url) do
    with {:ok, %{"transactions" => transactions}} <-
           @http_client.get(server_url <> "/api/transactions", %{
             "filter[confirmed]" => false
           }) do
      Enum.map(transactions, fn transaction_params ->
        case get_transaction(transaction_params["id"]) do
          nil ->
            case insert_transaction(transaction_params, server_url) do
              {:ok, transaction} ->
                transaction

              {:error, message} ->
                raise message
            end

          %Transaction{} = transaction ->
            if transaction.signature != transaction_params["signature"] do
              raise "Transaction with same id but other signature already known."
            else
              transaction
            end
        end
      end)
    else
      {:ok, %{"error" => error}} ->
        Logger.error(error)

      {:error, error} ->
        Logger.error(error)
    end
  end

  def order_scores_for_insertion(transactions) do
    Enum.reduce(transactions, [], &add_score_tree_to_result(&1, transactions, &2))
  end

  def add_score_tree_to_result(score, transactions, result) do
    case score in result do
      true ->
        result

      false ->
        if score["predecessor_id"] == nil do
          result ++ [score]
        else
          case Enum.find(transactions, &(&1["id"] == score["predecessor_id"])) do
            nil ->
              result ++ [score]

            pre_score ->
              result = add_score_tree_to_result(pre_score, transactions, result)
              result ++ [score]
          end
        end
    end
  end

  def insert_transaction(
        %{"user_id" => user_id, "data" => data} = transaction_params,
        server_url \\ nil
      ) do
    data = Poison.decode!(data)

    user =
      case User.get_user(user_id) do
        %User{} = user ->
          user

        nil ->
          User.get_user_from_server(user_id, server_url)
      end

    games =
      Enum.map(data["games"], fn game ->
        users = Enum.map(game["users"] || [], &User.get_user(&1))
        Map.put(game, "users", users)
      end)

    block_index = transaction_params["block_index"] || nil

    block =
      case block_index do
        nil ->
          nil

        block_index ->
          get_block(block_index)
      end

    transaction_params =
      transaction_params
      |> Map.drop(["user_id", "block_index"])
      |> Map.put("user", user)
      |> Map.put("block", block)
      |> Map.put("scores", order_scores_for_insertion(data["scores"]))
      |> Map.put("games", games)

    %Transaction{}
    |> Repo.preload([:user, :block])
    |> Transaction.changeset_p2p(transaction_params)
    |> Repo.insert()
  end

  # @doc "Validate the complete blockchain"
  # def valid?(blockchain) when is_list(blockchain) do
  #   zero =
  #     Enum.reduce_while(blockchain, nil, fn prev, current ->
  #       cond do
  #         current == nil ->
  #           {:cont, prev}

  #         Block.valid?(current, prev) ->
  #           {:cont, prev}

  #         true ->
  #           {:halt, false}
  #       end
  #     end)

  #   if zero, do: Block.valid?(zero), else: false
  # end
end
