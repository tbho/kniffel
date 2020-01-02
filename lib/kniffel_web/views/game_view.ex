defmodule KniffelWeb.GameView do
  use KniffelWeb, :view

  alias Kniffel.Game

  def show_roll_button?(game_id, user_id) do
    Game.count_score_types_for_game_and_user(game_id, user_id) < 13
  end
end
