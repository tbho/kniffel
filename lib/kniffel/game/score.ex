defmodule Kniffel.Game.Score do
  use Ecto.Schema
  import Ecto.Changeset

  alias Kniffel.Server
  alias Kniffel.Blockchain.Crypto
  alias Kniffel.Game.Score

  @primary_key {:id, :id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "score" do
    field(:dices, :map)
    field(:score_type, ScoreType, default: :none)
    field :signature, :string

    belongs_to(:predecessor, Kniffel.Game.Score)
    belongs_to(:user, Kniffel.User, type: :string)
    belongs_to(:game, Kniffel.Game)
    belongs_to(:server, Kniffel.Server, type: :string)
    belongs_to(:transaction, Kniffel.Blockchain.Transaction)

    timestamps()
  end

  @doc false
  def changeset(score, attrs) do
    server = Server.get_authorized_server()

    dices_to_roll =
      Enum.reduce(["a", "b", "c", "d", "e"], [], fn capital, acc ->
        case attrs["dices_to_roll_#{capital}"] || nil do
          "on" ->
            acc ++ [capital]

          nil ->
            acc
        end
      end)

    {:ok, response} =
      HTTPoison.post(
        server.url <> "/api/servers/roll",
        Poison.encode!(%{dices_to_roll: dices_to_roll}),
        [
          {"Content-Type", "application/json"}
        ]
      )

    %{"dices" => dices, "signature" => signature, "timestamp" => timestamp} =
      Poison.decode!(response.body)

    attrs =
      attrs
      |> Map.drop(["dices"])
      |> Map.put("dices", dices)
      |> Map.put("signature", signature)
      |> Map.put("server", server)
      |> Map.put("inserted_at", timestamp)

    score
    |> cast(attrs, [:dices, :score_type, :signature, :inserted_at])
    |> put_assoc(:predecessor, attrs["predecessor"] || score.predecessor)
    |> put_assoc(:user, attrs["user"] || score.user)
    |> put_assoc(:game, attrs["game"] || score.game)
    |> put_assoc(:server, attrs["server"] || score.server)
    |> put_assoc(:transaction, attrs["transaction"] || score.transaction)

    # |> unique_constraint("predecessor")
  end

  @doc false
  def changeset_p2p(score, attrs) do
    score
    |> cast(attrs, [
      :id,
      :dices,
      :score_type,
      :predecessor_id,
      :user_id,
      :game_id,
      :inserted_at,
      :signature,
      :server_id
    ])
    |> verify_changeset
  end

  @doc "Verify a block using the public key present in it"
  def verify_changeset(%Ecto.Changeset{} = changeset) do
    with %Ecto.Changeset{} <- changeset,
         {_, signature} <- fetch_field(changeset, :signature),
         {_, server_id} <- fetch_field(changeset, :server_id),
         {_, dices} <- fetch_field(changeset, :dices),
         {_, timestamp} <- fetch_field(changeset, :inserted_at),
         %Server{} = server <- Server.get_server(server_id) do
      {:ok, timestamp} = DateTime.from_naive(timestamp, "Etc/UTC")

      case Crypto.verify(
             Poison.encode!(%{"dices" => dices, "timestamp" => DateTime.to_string(timestamp)}),
             server.public_key,
             signature
           ) do
        :ok ->
          changeset

        :invalid ->
          add_error(changeset, :signature, "invalid",
            additional: "signature is not valid for dices field"
          )
      end
    end
  end

  @doc false
  def changeset_update(score, attrs) do
    score
    |> cast(attrs, [:score_type])
  end

  def calculate_scores(scores, users) do
    Enum.reduce(users, %{}, fn user, user_acc ->
      score_result =
        Enum.reduce(
          [
            :aces,
            :twos,
            :threes,
            :fours,
            :fives,
            :sixes,
            :three_of_a_kind,
            :four_of_a_kind,
            :full_house,
            :small_straight,
            :large_straight,
            :kniffel,
            :chance
          ],
          %{},
          fn type, type_acc ->
            score = score_exists?(scores, user.id, type)

            if score do
              dices = get_rolls_to_show(score)
              {location, dices} = Map.pop(dices, "location")
              points = calculate_score(dices, type)
              Map.put(type_acc, type, %{location: location, dices: dices, points: points})
            else
              type_acc
            end
          end
        )

      sum_up =
        Enum.reduce([:aces, :twos, :threes, :fours, :fives, :sixes], 0, fn type, acc ->
          %{points: points} = Map.get(score_result, type, %{points: 0})
          acc + points
        end)

      sum_down =
        Enum.reduce(
          [
            :three_of_a_kind,
            :four_of_a_kind,
            :full_house,
            :small_straight,
            :large_straight,
            :kniffel,
            :chance
          ],
          0,
          fn type, acc ->
            %{points: points} = Map.get(score_result, type, %{points: 0})
            acc + points
          end
        )

      bonus =
        if sum_up >= 63 do
          35
        else
          0
        end

      score_result =
        score_result
        |> Map.put(:sum_up, %{points: sum_up, location: :sum})
        |> Map.put(:bonus, %{points: bonus, location: :sum})
        |> Map.put(:sum_bonus, %{points: sum_up + bonus, location: :sum})
        |> Map.put(:sum_down, %{points: sum_down, location: :sum})
        |> Map.put(:sum_complete, %{points: sum_up + bonus + sum_down, location: :sum})

      Map.put(user_acc, user.id, score_result)
    end)
  end

  def score_exists?(scores, user_id, score_type) do
    Enum.find(scores, fn score ->
      score.user_id == user_id && score.score_type == score_type
    end)
  end

  def get_rolls_to_show(roll) do
    Enum.reduce(["a", "b", "c", "d", "e"], %{"location" => :block}, fn type, result ->
      {location_temp, dice} = find_score_in_history(roll, type)

      location =
        case {result["location"], location_temp} do
          {:block, :transaction} ->
            :transaction

          {:block, :none} ->
            :none

          {:transaction, :none} ->
            :none

          {other, _} ->
            other
        end

      result
      |> Map.put(type, dice)
      |> Map.put("location", location)
    end)
  end

  def find_score_in_history(nil, _), do: nil

  def find_score_in_history(%Score{dices: dices} = roll, type) do
    case Map.get(dices, type) do
      nil ->
        find_score_in_history(roll.predecessor, type)

      dice ->
        cond do
          roll.transaction && roll.transaction.block ->
            {:block, dice}

          roll.transaction ->
            {:transaction, dice}

          true ->
            {:none, dice}
        end
    end
  end

  def calculate_score(roll, type) do
    case type do
      :aces ->
        calculate_number(roll, 1)

      :twos ->
        calculate_number(roll, 2)

      :threes ->
        calculate_number(roll, 3)

      :fours ->
        calculate_number(roll, 4)

      :fives ->
        calculate_number(roll, 5)

      :sixes ->
        calculate_number(roll, 6)

      :three_of_a_kind ->
        result = count_occurences(roll)

        if 3 in Map.values(result) || 4 in Map.values(result) || 5 in Map.values(result) do
          calculate_roll(roll)
        else
          0
        end

      :four_of_a_kind ->
        result = count_occurences(roll)

        if 4 in Map.values(result) || 5 in Map.values(result) do
          calculate_roll(roll)
        else
          0
        end

      :full_house ->
        result = count_occurences(roll)

        if 3 in Map.values(result) && 2 in Map.values(result) do
          25
        else
          0
        end

      :small_straight ->
        if Enum.all?([1, 2, 3, 4], fn x -> contains_number?(roll, x) end) ||
             Enum.all?([2, 3, 4, 5], fn x -> contains_number?(roll, x) end) ||
             Enum.all?([3, 4, 5, 6], fn x -> contains_number?(roll, x) end) do
          30
        else
          0
        end

      :large_straight ->
        if Enum.all?([1, 2, 3, 4, 5], fn x -> contains_number?(roll, x) end) ||
             Enum.all?([2, 3, 4, 5, 6], fn x -> contains_number?(roll, x) end) do
          40
        else
          0
        end

      :kniffel ->
        result = count_occurences(roll)

        if 5 in Map.values(result) do
          50
        else
          0
        end

      :chance ->
        calculate_roll(roll)
    end
  end

  def calculate_number(roll, number) do
    Enum.reduce(roll, 0, fn {_, x}, result ->
      if x == number do
        result + x
      else
        result
      end
    end)
  end

  def calculate_roll(roll) do
    Enum.reduce(roll, 0, fn {_type, x}, result ->
      result + x
    end)
  end

  def contains_number?(roll, number) do
    Enum.any?(roll, fn {_type, x} -> x == number end)
  end

  def count_occurences(roll) do
    Enum.reduce(roll, %{}, fn {_type, x}, result ->
      temp = Map.get(result, x, 0)
      Map.put(result, x, temp + 1)
    end)
  end
end
