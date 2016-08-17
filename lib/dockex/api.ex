defmodule Dockex.API do
  use HTTPoison.Base

  def process_url(url) do
    base_url <> url
  end

  def process_response_body(body) do
    body
  end

  def process_request_headers(headers) do
    headers
    |> Enum.into([{"Content-Type", "application/json"}])
  end

  def request(method, url, body \\ "", headers \\ [], options \\ []) do
    options = options
    |> Keyword.merge([hackney: ssl_options])

    super(method, url, body, headers, options)
  end

  defp ssl_options do
    [
      ssl_options: [
        certfile: Dockex.Config.get.ssl_certificate,
        keyfile: Dockex.Config.get.ssl_key,
      ]
    ]
  end

  defp base_url, do: Dockex.Config.get.base_url
end
