defmodule Kniffel do
  @moduledoc """
  Kniffel keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  def request do
    Application.get_env(:kniffel, :request)
  end
end
