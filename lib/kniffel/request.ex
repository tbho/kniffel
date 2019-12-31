defmodule Kniffel.Request do
  def get(url) do
    HTTPoison.get(url, [
      {"Content-Type", "application/json"}
    ])
    |> handle_response
  end

  def post(url, params) do
    HTTPoison.post(url, Poison.encode!(params), [
      {"Content-Type", "application/json"}
    ])
    |> handle_response
  end

  def handle_response(response) do
    with {:request, {:ok, response}} <- {:request, response},
         {:status_code, 200} <- {:status_code, response.status_code},
         true <- {"content-type", "application/json; charset=utf-8"} in response.headers,
         {:json, {:ok, response_body}} <- {:json, Poison.decode(response.body)} do
      {:ok, response_body}
    else
      {:request, {:error, _message}} ->
        {:error, "request_failed"}

      {:status_code, _status_code} ->
        {:error, "status_code"}

      false ->
        {:error, "wrong_content_type"}

      {:json, {:error, _message}} ->
        {:error, "decode_failed"}
    end
  end
end
