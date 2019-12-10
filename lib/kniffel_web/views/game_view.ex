defmodule KniffelWeb.GameView do
  use KniffelWeb, :view

  def score_exists?(scores, user_id, score_type) do
    Enum.find(scores, fn score ->
      score.user_id == user_id && score.score_type == score_type
    end)
  end

  alias Kniffel.Game.Score

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
