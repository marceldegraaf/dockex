defmodule Dockex.Client do
  use GenServer

  defmodule Config do
    defstruct base_url: "", ssl_certificate: nil, ssl_key: nil
  end

  def start_link(%Dockex.Client.Config{} = config) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @doc """
  Initialize the Dockex client. Accepts a `%Dockex.Client.Config{}` struct
  containing the connection details and TLS certificate paths.
  """
  @spec init(struct) :: {:ok, map}
  def init(config) do
    {:ok, _pid} = Dockex.Config.start_link(config)
    {:ok, _} = ping

    {:ok, %{config: config}}
  end

  @doc """
  Ping the Docker server to check if it's up and if the connection
  configuration is correct.
  """
  @spec ping() :: {:ok, String.t} | {:error, String.t}
  def ping do
    case Dockex.API.get("/_ping") do
      {:ok, %HTTPoison.Response{status_code: 200, body: "OK"}} -> {:ok, ""}
      {:error, %HTTPoison.Error{reason: reason}} -> {:error, reason}
    end
  end

  @doc """
  Query the Docker server for runtime information.
  """
  @spec info() :: {:ok, map} | {:error, String.t}
  def info do
    case Dockex.API.get("/info") do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} -> Poison.decode(body)
      {:error, %HTTPoison.Error{reason: reason}} -> {:error, reason}
    end
  end

  @doc """
  List running containers.
  """
  @spec list_containers() :: {:ok, map} | {:error, String.t}
  def list_containers do
    case Dockex.API.get("/containers/json") do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} -> Poison.decode(body)
      {:error, %HTTPoison.Error{reason: reason}} -> {:error, reason}
    end
  end

  @doc """
  Inspect a container. Accepts a `%Dockex.Container{}` struct or a container id.
  """
  @spec inspect_container(struct | number) :: {:ok, map} | {:error, String.t}
  def inspect_container(%Dockex.Container{id: id}), do: inspect_container(id)
  def inspect_container(id) do
    case Dockex.API.get("/containers/#{id}/json") do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} -> Poison.decode(body)
      {:error, %HTTPoison.Error{reason: reason}} -> {:error, reason}
    end
  end

  @doc """
  Fetch the last 50 lines of container logs.
  """
  @spec get_container_logs(struct | number) :: {:ok, String.t} | {:error, String.t}
  def get_container_logs(%Dockex.Container{id: id}), do: get_container_logs(id)
  def get_container_logs(id), do: get_container_logs(id, 50)

  @doc """
  Fetch the last `number` lines of container logs.
  """
  @spec get_container_logs(struct | number, number) :: {:ok, String.t} | {:error, String.t}
  def get_container_logs(%Dockex.Container{id: id}, number), do: get_container_logs(id, number)
  def get_container_logs(id, number) do
    case Dockex.API.get("/containers/#{id}/logs", [], params: %{stdout: 1, tail: number}) do
      {:ok, %HTTPoison.Response{status_code: 200, body: ""}} -> {:ok, ""}
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        <<type, 0, 0, 0, _size :: integer-big-size(32), output :: binary>> = body
        {:ok, output}
      {:error, %HTTPoison.Error{reason: reason}} -> {:error, reason}
    end
  end

  @doc """
  Create and start a container at the same time.
  """
  @spec create_and_start_container(struct) :: {:ok, struct}
  def create_and_start_container(%Dockex.Container{} = container) do
    with \
      {:ok, container} <- create_container(container),
      {:ok, container} <- start_container(container)
    do \
      {:ok, container}
    end
  end

  @doc """
  Create a container.
  """
  @spec create_container(struct) :: {:ok, struct} | {:error, String.t}
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

  @doc """
  Start a previously created container.
  """
  @spec start_container(struct) :: {:ok, struct} | {:error, String.t}
  def start_container(%Dockex.Container{id: id} = container) do
    case Dockex.API.post("/containers/#{id}/start", "", [], []) do
      {:ok, %HTTPoison.Response{status_code: 204}} -> {:ok, container}
      {:ok, %HTTPoison.Response{status_code: 304}} -> {:ok, container}
      {:error, %HTTPoison.Error{reason: reason}} -> {:error, reason}
    end
  end
end
