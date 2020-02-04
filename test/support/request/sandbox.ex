defmodule Kniffel.Request.Sandbox do
  @behaviour Kniffel.Request

  require Logger

  def get(url, params \\ %{})

  def get(url, params) do
    url_regex = ~r/https?:\/\/([a-z0-9]*\.[a-z]*:?[0-9]*)([\/a-z0-9]*)/
    ip_regex = ~r/([0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}:?[0-9]*)([\/a-z0-9]*)/

    [[url, server_url, path]] =
      cond do
        String.match?(url, url_regex) ->
          Regex.scan(url_regex, url)

        String.match?(url, ip_regex) ->
          Regex.scan(ip_regex, url)
      end

    Kniffel.Cache.get({server_url, path})
  end

  def post(url, params) do
    url_regex = ~r/https?:\/\/([a-z0-9]*\.[a-z]*:?[0-9]*)([\/a-z0-9]*)/
    ip_regex = ~r/([0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}:?[0-9]*)([\/a-z0-9]*)/

    [[url, server_url, path]] =
      cond do
        String.match?(url, url_regex) ->
          Regex.scan(url_regex, url)

        String.match?(url, ip_regex) ->
          Regex.scan(ip_regex, url)
      end

    with cache_params <- Kniffel.Cache.get({server_url, path, :params}),
         false <- is_nil(cache_params),
         response <- Kniffel.Cache.get({server_url, path}),
         false <- is_nil(response),
         true <- maps_match?(cache_params, params) do
      response
    else
      true ->
        raise "cache not set"

      false ->
        raise "params do not equal"
    end
  end

  defp maps_match?(a, b, check_recursive \\ true) do
    Enum.all?(a, fn {key, value} ->
      case Map.has_key?(b, key) do
        true ->
          if check_recursive do
            cond do
              is_map(value) ->
                maps_match?(value, Map.get(b, key))

              value ->
                value == Map.get(b, key)
            end
          else
            true
          end

        false ->
          false
      end
    end)
  end
end
