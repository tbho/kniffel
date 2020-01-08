defmodule Kniffel.Scheduler.RoundSpecification do
  alias Kniffel.Server
  alias Kniffel.Scheduler.RoundSpecification
  require Logger

  # in seconds
  @default_round_length 30
  # Offset (in seconds)
  @round_offset 2

  defstruct round_length: @default_round_length,
            round_begin: Timex.now(),
            # Timex.add(
            #   Timex.now(),
            #   Timex.Duration.from_seconds(@default_round_length + @round_offset)
            # ),
            round_number: 1

  def get_round_time(%RoundSpecification{round_begin: round_begin}, :round_begin) do
    round_begin
  end

  def get_round_time(
        %RoundSpecification{round_begin: round_begin},
        :next_round
      ) do
    round_begin
  end

  def get_round_time(
        %RoundSpecification{round_begin: round_begin, round_length: round_length},
        :propose_block
      ) do
    duration =
      round_length
      |> Timex.Duration.from_seconds()
      |> Timex.Duration.scale(1 / 3)

    Timex.add(round_begin, duration)
  end

  def get_round_time(
        %RoundSpecification{round_begin: round_begin, round_length: round_length},
        :commit_block
      ) do
    duration =
      round_length
      |> Timex.Duration.from_seconds()
      |> Timex.Duration.scale(2 / 3)

    Timex.add(round_begin, duration)
  end

  def get_round_time(
        %RoundSpecification{round_begin: round_begin, round_length: round_length},
        :finalize_block
      ) do
    duration =
      round_length
      |> Timex.Duration.from_seconds()

    Timex.add(round_begin, duration)
  end

  def get_round_time(%RoundSpecification{} = round_specification, :cancel_block_propose),
    do: get_round_time(round_specification, :propose_block)

  def get_round_time(%RoundSpecification{} = round_specification, :cancel_block_commit),
    do: get_round_time(round_specification, :commit_block)

  def get_round_time(_round_specification, _name), do: nil

  def calculate_diff_to_now(time, unit \\ :milliseconds) do
    Timex.diff(time, Timex.now(), unit)
  end

  def get_round_specification(), do: get_round_from_cache(:round_specification)
  def get_next_round_specification(), do: get_round_from_cache(:next_round_specification)

  defp get_round_from_cache(key) do
    case Kniffel.Cache.get(key) do
      %RoundSpecification{} = round_specification ->
        round_specification

      nil ->
        {:error, :no_round_specification_in_cache}
    end
  end

  def set_round_specification(%RoundSpecification{} = round_specification) do
    Kniffel.Cache.set(:round_specification, round_specification)
    round_specification
  end

  def set_next_round_specification(%RoundSpecification{} = round_specification) do
    round_specification = calculate_next_round_specification(round_specification)
    Kniffel.Cache.set(:next_round_specification, round_specification)
    round_specification
  end

  def calculate_next_round_specification(
        %RoundSpecification{
          round_length: round_length,
          round_number: round_number,
          round_begin: round_begin
        } = round_specification
      ) do

    duration =
      round_length + @round_offset
      |> Timex.Duration.from_seconds()

    %RoundSpecification{
      round_length: round_length,
      round_begin: Timex.add(round_begin, duration),
      round_number: round_number + 1
    }
  end

  def start_new_round() do
    Logger.debug("--- Set next round_specification")
    with %RoundSpecification{} = next_round_specification <- get_next_round_specification() do
      set_round_specification(next_round_specification)
      set_next_round_specification(next_round_specification)
    else
      other ->
        other
    end
  end

  def request_round_specification_from_network() do
    servers = Server.get_authorized_servers(false)

    round_specification_responses =
      Enum.reduce(servers, [], fn server, result ->
        with {:ok, %{"round_response" => round_response}} <-
               Kniffel.Request.get(server.url <> "/api/sheduler/next_round") do
          {:ok, round_begin} = Timex.parse(round_response["round_begin"], "{ISO:Extended}")

          case Timex.compare(Timex.now(), round_begin) do
            -1 ->
              result ++
                [
                  %RoundSpecification{
                    round_length: round_response["round_length"],
                    round_begin: round_begin,
                    round_number: round_response["round_number"]
                  }
                ]

            0 ->
              result

            1 ->
              result
          end
        else
          {:ok, %{"error" => error}} ->
            Logger.error(error)
            result

          {:error, error} ->
            Logger.error(error)
            result
        end
      end)

    # if no server is in network empty list is returned
    # otherwise answers will be grouped and answer with highest count is choosen
    with false <- Enum.empty?(round_specification_responses),
         uniq_specs <- Enum.uniq(round_specification_responses),
         grouped_specs <-
           Enum.map(uniq_specs, fn uniq_spec ->
             {uniq_spec, Enum.count(round_specification_responses, &(uniq_spec == &1))}
           end),
         sort_specs <- Enum.sort_by(grouped_specs, &elem(&1, 1), &>=/2) do
      {round_specification, _count} = List.first(sort_specs)
      Logger.debug("got round_specification from network: #{inspect(round_specification)}")

      if round_specification do
        Kniffel.Cache.set(:next_round_specification, round_specification)
        :ok
      else
        round_specification = get_default_round_specification()

        Logger.debug(
          "round_specification from network is nil, setting default now: #{
            inspect(round_specification)
          }"
        )

        Kniffel.Cache.set(:next_round_specification, round_specification)
        :default
      end
    else
      true ->
        round_specification = get_default_round_specification()

        Logger.debug(
          "no round_specifications recieved from network, setting default now: #{
            inspect(round_specification)
          }"
        )

        Kniffel.Cache.set(:next_round_specification, round_specification)
        :default
    end
  end

  def get_default_round_specification() do
    time_now =
      Timex.add(
        Timex.now(),
        Timex.Duration.from_seconds(@default_round_length + @round_offset)
      )

    %RoundSpecification{
      round_length: @default_round_length,
      round_begin: time_now,
      round_number: 1
    }
  end

  def cast(params) do
    {:ok, round_begin} = Timex.parse(params["round_begin"], "{ISO:Extended}")

    %RoundSpecification{
      round_length: params["round_length"],
      round_begin: round_begin,
      round_number: params["round_number"]
    }
  end

  def json(%RoundSpecification{} = round_specification) do
    %{
      round_length: round_specification.round_length,
      round_begin: round_specification.round_begin,
      round_number: round_specification.round_number
    }
  end
end
