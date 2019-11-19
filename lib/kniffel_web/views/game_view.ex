defmodule KniffelWeb.GameView do
  use KniffelWeb, :view

  def display_score(scores, user_id, score_type) do
    Enum.find(scores, fn score ->
      score.user_id == user_id && score.score_type == score_type
    end)
  end

  alias Kniffel.Game.Score

  def get_rolls_to_show(roll) do
    Enum.reduce(["a", "b", "c", "d", "e"], %{}, fn type, result ->
      Map.put(result, type, find_score_in_history(roll, type))
    end)
  end

  def find_score_in_history(nil, _), do: nil

  def find_score_in_history(%Score{dices: dices} = roll, type) do
    case Map.get(dices, type) do
      nil ->
        find_score_in_history(roll.predecessor, type)

      dice ->
        dice
    end
  end
end
