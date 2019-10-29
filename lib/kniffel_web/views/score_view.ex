defmodule KniffelWeb.ScoreView do
  use KniffelWeb, :view

  alias ScoreType


  def is_allowed_to_roll_again(roll) do
    is_allowed_to_roll_again(roll, 3)
  end

  def is_allowed_to_roll_again(_, 0), do: false
  def is_allowed_to_roll_again(nil, _), do: true

  def is_allowed_to_roll_again(roll, limit) do
    is_allowed_to_roll_again(roll.predecessor, limit - 1)
  end

  alias Kniffel.Game.Roll

  def get_rolls_to_show(roll) do
    Enum.reduce(["a", "b", "c", "d", "e"], %{}, fn type, result ->
      Map.put(result, type, find_score_in_history(roll, type))
    end)
  end

  def find_score_in_history(nil, _), do: nil

  def find_score_in_history(%Roll{dices: dices} = roll, type) do
    case Map.get(dices, type) do
      nil ->
        find_score_in_history(roll.predecessor, type)

      dice ->
        dice
    end
  end
end
