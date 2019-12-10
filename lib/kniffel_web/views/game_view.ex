defmodule KniffelWeb.GameView do
  use KniffelWeb, :view

  def display_score(scores, user_id, score_type) do
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
end
