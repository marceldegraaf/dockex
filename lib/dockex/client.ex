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
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} -> Poison.decode(body)
      {:error, %HTTPoison.Error{reason: reason}} -> {:error, reason}
    end
  end

  def list_containers do
    case Dockex.API.get("/containers/json") do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} -> Poison.decode(body)
      {:error, %HTTPoison.Error{reason: reason}} -> {:error, reason}
    end
  end

  def show_container(%Dockex.Container{id: id}), do: show_container(id)
  def show_container(id) do
    case Dockex.API.get("/containers/#{id}/json") do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} -> Poison.decode(body)
      {:error, %HTTPoison.Error{reason: reason}} -> {:error, reason}
    end
  end

  def get_container_logs(%Dockex.Container{id: id}), do: get_container_logs(id)
  def get_container_logs(id), do: get_container_logs(id, 50)

  def get_container_logs(%Dockex.Container{id: id}, lines), do: get_container_logs(id, lines)
  def get_container_logs(id, lines) do
    case Dockex.API.get("/containers/#{id}/logs", [], params: %{stdout: 1, tail: lines}) do
      {:ok, %HTTPoison.Response{status_code: 200, body: ""}} -> {:ok, ""}
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        <<type, 0, 0, 0, _size :: integer-big-size(32), output :: binary>> = body
        {:ok, output}
      {:error, %HTTPoison.Error{reason: reason}} -> {:error, reason}
    end
  end

  def create_and_start_container(%Dockex.Container{} = container) do
    with \
      {:ok, container} <- create_container(container),
      {:ok, container} <- start_container(container)
    do \
      {:ok, container}
    end
  end

  def create_container(%Dockex.Container{} = container) do
    {name, container} = container |> Map.pop(:name)
    {:ok, body} = container |> Poison.encode

    case Dockex.API.post("/containers/create", body, [], params: %{name: name}) do
      {:ok, %HTTPoison.Response{status_code: 201, body: body}} ->
        {:ok, body} = Poison.decode(body)
        {:ok, %Dockex.Container{container | id: body["Id"]}}
      {:ok, %HTTPoison.Response{status_code: 409, body: message}} -> {:error, message}
      {:error, %HTTPoison.Error{reason: reason}} -> {:error, reason}
    end
  end

  def start_container(%Dockex.Container{} = container) do
    case Dockex.API.post("/containers/#{container.id}/start", "", [], []) do
      {:ok, %HTTPoison.Response{status_code: 204}} -> {:ok, container}
      {:ok, %HTTPoison.Response{status_code: 304}} -> {:ok, container}
      {:error, %HTTPoison.Error{reason: reason}} -> {:error, reason}
    end
  end
end
