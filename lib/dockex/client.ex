defmodule Dockex.Client do
  use GenServer

  defmodule Config do
    defstruct base_url: "", ssl_certificate: nil, ssl_key: nil
  end

  def start_link(%Dockex.Client.Config{} = config) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  def init(config) do
    {:ok, _pid} = Dockex.Config.start_link(config)
    {:ok, _} = ping

    {:ok, %{config: config}}
  end

  def ping do
    case Dockex.API.get("/_ping") do
      {:ok, %HTTPoison.Response{status_code: 200, body: "OK"}} -> {:ok, ""}
      {:error, %HTTPoison.Error{reason: reason}} -> {:error, reason}
    end
  end

  def info do
    case Dockex.API.get("/info") do
      {:ok, %HTTPoison.Response{status_code: 200, body: "OK"}} -> {:ok, ""}
      {:error, %HTTPoison.Error{reason: reason}} -> {:error, reason}
    end
  end

  def list_containers do
    case Dockex.API.get("/containers/json") do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} -> Poison.decode(body)
      {:error, %HTTPoison.Error{reason: reason}} -> {:error, reason}
    end
  end
end
