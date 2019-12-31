defmodule Kniffel.Blockchain.Block.ServerAge do
  alias Kniffel.Blockchain.{Block, Block.ServerAge}
  alias Kniffel.Server

  import Ecto.Query, warn: false

  alias Kniffel.Repo

  @age_calculation_select_limit 10

  defstruct ages: [],
            checked_at_block: 0,
            offsets: []

  def get_server_age(refresh_list \\ false) do
    cache_result = Kniffel.Cache.get(:server_age)

    if refresh_list || is_nil(cache_result) do
      servers = Server.get_authorized_servers()
      last_block = Kniffel.Blockchain.get_last_block()

      server_age =
        calculate_ages_of_servers_from_blockchain(
          0,
          @age_calculation_select_limit,
          servers,
          %ServerAge{}
        )

      server_age = add_server_ages_not_in_blockchain(servers, server_age)

      %{server_age | checked_at_block: last_block.index}

      Kniffel.Cache.set(:server_age, server_age)
      server_age
    else
      cache_result
    end
  end

  def calculate_ages_of_servers_from_blockchain(offset, limit, servers, result) do
    blocks =
      Block
      |> order_by(desc: :index)
      |> limit(^limit)
      |> offset(^offset)
      |> Repo.all()

    {result, offset} =
      Enum.reduce(blocks, {result, offset}, fn block, {result, offset} ->
        {%{result | ages: result.ages ++ [{block.server_id, offset}]}, offset + 1}
      end)

    cond do
      Enum.all?(servers, fn server -> Map.get(result, server.id) != nil end) ->
        result

      length(blocks) < limit ->
        result

      true ->
        calculate_ages_of_servers_from_blockchain(offset, limit, servers, result)
    end
  end

  def update_server_ages(server_age) do
    blocks =
      Block
      |> order_by(desc: :index)
      |> where([b], b.index > ^server_age.checked_at_block)
      |> Repo.all()

    shift_server_ages(server_age, length(blocks))

    Enum.reduce(blocks, {server_age, 0}, fn block, {server_age, offset} ->
      List.delete(server_age, get_entry_by_server_id(server_age, block.server_id))
      {%{server_age | ages: server_age.ages ++ {block.server_id, offset}}, offset + 1}
    end)
  end

  defp add_server_ages_not_in_blockchain(servers, result \\ %ServerAge{}) do
    Enum.reduce(servers, result, fn server, result ->
      case contains_server?(result, server.id) do
        false ->
          result = shift_server_ages(result, 1)

          %{result | ages: result.ages ++ [{server.id, 0}]}

        true ->
          result
      end
    end)
  end

  defp shift_server_ages(server_age, offset) do
    %{
      server_age
      | ages:
          Enum.map(server_age.ages, fn {server_id, age} ->
            {server_id, age + offset}
          end)
    }
  end

  defp contains_server?(server_age, filter_server_id) do
    Enum.any?(server_age.ages, fn {server_id, _age} ->
      filter_server_id == server_id
    end)
  end

  defp get_entry_by_server_id(server_age, filter_server_id) do
    Enum.find(server_age.ages, fn {server_id, _age} ->
      server_id == filter_server_id
    end)
  end

  def is_leader?(server_id) do
    1 == get_position_in_server_queue(server_id)
  end

  def get_position_in_server_queue(server_id) do
    with server_age when not is_nil(server_age) <- get_server_age(),
         server_ages <- Enum.sort_by(server_age.ages, &elem(&1, 1), &>=/2) do
      {position, _changed} =
        Enum.reduce(server_ages, {1, false}, fn
          _position_result, {position, true} ->
            {position, true}

          position_result, {position, false} ->
            if server_id == elem(position_result, 0) do
              {position, true}
            else
              {position + 1, false}
            end
        end)

      position
    end
  end
end
