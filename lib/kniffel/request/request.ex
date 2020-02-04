defmodule Kniffel.Request do
  @callback get(url :: String.t(), params :: Map.t()) :: {:ok, Map} | {:error, String.t()}
  @callback post(url :: String.t(), params :: Map.t()) :: {:ok, Map} | {:error, String.t()}
end
