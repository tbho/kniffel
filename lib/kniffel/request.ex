defmodule Kniffel.Request do
  require Logger

  def get(url) do
    {error, _} =
      response =
      HTTPoison.get(url, [
        {"Content-Type", "application/json"}
      ])
      |> IO.inspect()

    if :error == error do
      IO.inspect(url)
      IO.inspect(response)
    end

    response
    |> handle_response
  end

  def post(url, params) do
    {error, _} =
      response =
      HTTPoison.post(url, Poison.encode!(params), [
        {"Content-Type", "application/json"}
      ])
      |> IO.inspect()

    if :error == error do
      IO.inspect(url)
      IO.inspect(params)
      IO.inspect(response)
    end

    response
    |> handle_response
  end

  def handle_response(response) do
    with {:request, {:ok, response}} <- {:request, response},
         {:status_code, 200} <- {:status_code, response.status_code},
         #  true <- {"Content-Type", "application/json; charset=utf-8"} in response.headers,
         {:json, {:ok, response_body}} <- {:json, Poison.decode(response.body)} do
      {:ok, response_body}
    else
      {:request, {:error, message}} ->
        {:ok, %{body: body}} = response
        Logger.debug(message)
        Logger.debug(body)
        {:error, "request_failed"}

      {:status_code, status_code} ->
        {:ok, %{body: body}} = response
        Logger.debug(status_code)
        Logger.debug(body)
        {:error, "status_code"}

      # false ->
      #   {:error, "wrong_content_type"}

      {:json, {:error, message}} ->
        {:ok, %{body: body}} = response
        Logger.debug(message)
        Logger.debug(body)
        {:error, "decode_failed"}
    end
  end
end
