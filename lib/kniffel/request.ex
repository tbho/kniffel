defmodule Kniffel.Request do

  require Logger

  @callback get(url :: String.t()) :: {:ok, Map} | {:error, String.t()}
  def get(url), do: get(url, %{})

  @callback get(url :: String.t(), params :: Map.t()) :: {:ok, Map} | {:error, String.t()}
  def get(url, params \\ %{}) do
    HTTPoison.get(
      url,
      [
        {"Content-Type", "application/json"}
      ],
      params: params
    )
    |> handle_response
  end

  @callback post(url :: String.t(), params :: Map.t()) :: {:ok, Map} | {:error, String.t()}
  def post(url, params) do
    HTTPoison.post(url, Poison.encode!(params), [
      {"Content-Type", "application/json"}
    ])
    |> handle_response
  end


  defp handle_response(response) do
    with {:request, {:ok, response}} <- {:request, response},
         {:status_code, 200} <- {:status_code, response.status_code},
         #  true <- {"Content-Type", "application/json; charset=utf-8"} in response.headers,
         {:json, {:ok, response_body}} <- {:json, Poison.decode(response.body)} do
      {:ok, response_body}
    else
      {:request, {:error, message}} ->
        Logger.debug(inspect(message))
        {:error, "request_failed"}

      {:status_code, status_code} ->
        Logger.debug(inspect(status_code))
        {:error, "status_code"}

      # false ->
      #   {:error, "wrong_content_type"}

      {:json, {:error, message}} ->
        Logger.debug(inspect(message))
        {:error, "decode_failed"}
    end
  end
end
