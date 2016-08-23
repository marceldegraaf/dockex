defmodule Dockex.Client do
  use GenServer

  defmodule Config do
    defstruct base_url: nil, ssl_certificate: nil, ssl_key: nil
  end

  def start_link(%Dockex.Client.Config{} = config) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @doc """
  Initialize the Dockex client. Accepts a `%Dockex.Client.Config{}` struct
  containing the connection details and TLS certificate paths.
  """
  @spec init(struct) :: {:ok, map}
  def init(config), do: {:ok, %{config: config}}

  #
  # Public API
  #

  @doc """
  Ping the Docker server to check if it's up and if the connection
  configuration is correct.
  """
  @spec ping(pid) :: {:ok, String.t} | {:error, String.t}
  def ping(pid), do: GenServer.call(pid, :ping)

  @doc """
  Query the Docker server for runtime information.
  """
  @spec info(pid) :: {:ok, map} | {:error, String.t}
  def info(pid), do: GenServer.call(pid, :info)

  @doc """
  List running containers.
  """
  @spec list_containers(pid) :: {:ok, list(map)} | {:error, String.t}
  def list_containers(pid), do: GenServer.call(pid, :list_containers)

  @doc """
  Inspect a container. Accepts a `%Dockex.Container{}` struct to specify
  which container to inspect.
  """
  @spec inspect_container(pid, struct) :: {:ok, map} | {:error, String.t}
  def inspect_container(pid, container) do
    GenServer.call(pid, {:inspect_container, container})
  end

  @doc """
  Fetch the last 50 lines of container logs.
  """
  @spec get_container_logs(pid, struct) :: {:ok, String.t} | {:error, String.t}
  def get_container_logs(pid, %Dockex.Container{} = container) do
    get_container_logs(pid, container, 50)
  end

  @doc """
  Fetch the last `number` lines of container logs.
  """
  @spec get_container_logs(pid, struct, number) :: {:ok, String.t} | {:error, String.t}
  def get_container_logs(pid, %Dockex.Container{} = container, number) do
    GenServer.call(pid, {:get_container_logs, container, number})
  end

  @doc """
  Create a container.
  """
  @spec create_container(pid, struct) :: {:ok, struct} | {:error, String.t}
  def create_container(pid, %Dockex.Container{} = container) do
    GenServer.call(pid, {:create_container, container})
  end

  @doc """
  Start a previously created container.
  """
  @spec start_container(pid, struct) :: {:ok, struct} | {:error, String.t}
  def start_container(pid, %Dockex.Container{} = container) do
    GenServer.call(pid, {:start_container, container})
  end

  @doc """
  Create and start a container at the same time.
  """
  @spec create_and_start_container(pid, struct) :: {:ok, struct} | {:error, String.t}
  def create_and_start_container(pid, %Dockex.Container{} = container) do
    with \
      {:ok, container} <- create_container(pid, container),
      {:ok, container} <- start_container(pid, container)
    do \
      {:ok, container}
    end
  end

  @doc """
  Stop a running container.
  """
  @spec stop_container(pid, struct) :: {:ok, struct} | {:error, String.t}
  def stop_container(pid, %Dockex.Container{} = container, timeout \\ nil) do
    GenServer.call(pid, {:stop_container, container, timeout})
  end

  @doc """
  Restart a running container.
  """
  @spec restart_container(pid, struct) :: {:ok, struct} | {:error, String.t}
  def restart_container(pid, %Dockex.Container{} = container, timeout \\ nil) do
    GenServer.call(pid, {:restart_container, container, timeout})
  end

  @doc """
  Delete a container.
  """
  @spec delete_container(pid, struct) :: {:ok, String.t} | {:error, String.t}
  def delete_container(pid, %Dockex.Container{} = container) do
    GenServer.call(pid, {:delete_container, container})
  end

  #
  # GenServer callbacks
  #

  def handle_call(:ping, _from, state) do
    result = case get("/_ping", state) do
      {:ok, %HTTPoison.Response{status_code: 200, body: "OK"}} -> {:ok, "OK"}
      {:error, %HTTPoison.Error{reason: reason}} -> {:error, to_string(reason)}
    end

    {:reply, result, state}
  end

  def handle_call(:info, _from, state) do
    result = case get("/info", state) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} -> Poison.decode(body)
      {:error, %HTTPoison.Error{reason: reason}} -> {:error, reason}
    end

    {:reply, result, state}
  end

  def handle_call(:list_containers, _from, state) do
    result = case get("/containers/json", state) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} -> Poison.decode(body)
      {:error, %HTTPoison.Error{reason: reason}} -> {:error, reason}
    end

    {:reply, result, state}
  end

  def handle_call({:inspect_container, %Dockex.Container{id: id}}, _from, state) do
    result = case get("/containers/#{id}/json", state) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} -> Poison.decode(body)
      {:error, %HTTPoison.Error{reason: reason}} -> {:error, reason}
    end

    {:reply, result, state}
  end

  # TODO This works:
  #
  #   Dockex.Client.get_container_logs(client, %Dockex.Container{id: "..."}, 1)
  #
  # But this still returns an unparsed bitstring:
  #
  #   Dockex.Client.get_container_logs(client, %Dockex.Container{id: ""}, 2)
  #
  # Probably because each new line starts with the same <<type, 0, 0, 0, _size ... >> information?
  #
  def handle_call({:get_container_logs, %Dockex.Container{id: id}, number}, _from, state) do
    result = case get("/containers/#{id}/logs", state, params: %{stdout: 1, tail: number}) do
      {:ok, %HTTPoison.Response{status_code: 200, body: ""}} ->
        {:ok, ""}

      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        <<type, 0, 0, 0, _size :: integer-big-size(32), output :: binary>> = body
        {:ok, output}

      {:ok, %HTTPoison.Response{status_code: 404, body: message}} ->
        {:error, message}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, reason}
    end

    {:reply, result, state}
  end

  def handle_call({:create_container, %Dockex.Container{} = container}, _from, state) do
    {name, container} = container |> Map.pop(:name)
    {:ok, body} = container |> Poison.encode

    result = case post("/containers/create", state, body, params: %{name: name}) do
      {:ok, %HTTPoison.Response{status_code: 201, body: body}} ->
        {:ok, body} = Poison.decode(body)
        {:ok, %Dockex.Container{container | id: body["Id"]}}

      {:ok, %HTTPoison.Response{status_code: 404, body: message}} ->
        {:error, message}

      {:ok, %HTTPoison.Response{status_code: 409, body: message}} ->
        {:error, message}

      {:ok, %HTTPoison.Response{status_code: 500, body: message}} ->
        {:error, message}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, reason}
    end

    {:reply, result, state}
  end

  def handle_call({:start_container, %Dockex.Container{id: id} = container}, _from, state) do
    result = case post("/containers/#{id}/start", state, "") do
      {:ok, %HTTPoison.Response{status_code: 204}} -> {:ok, container}
      {:ok, %HTTPoison.Response{status_code: 304}} -> {:ok, container}
      {:ok, %HTTPoison.Response{status_code: 404, body: message}} -> {:error, message}
      {:error, %HTTPoison.Error{reason: reason}} -> {:error, reason}
    end

    {:reply, result, state}
  end

  def handle_call({:stop_container, %Dockex.Container{id: id} = container, timeout}, _from, state) do
    result = case post("/containers/#{id}/stop", state, "", params: %{t: timeout}) do
      {:ok, %HTTPoison.Response{status_code: 204}} -> {:ok, container}
      {:ok, %HTTPoison.Response{status_code: 304}} -> {:ok, container}
      {:ok, %HTTPoison.Response{status_code: 404, body: message}} -> {:error, message}
      {:error, %HTTPoison.Error{reason: reason}} -> {:error, reason}
    end

    {:reply, result, state}
  end

  def handle_call({:restart_container, %Dockex.Container{id: id} = container, timeout}, _from, state) do
    result = case post("/containers/#{id}/restart", state, "", params: %{t: timeout}) do
      {:ok, %HTTPoison.Response{status_code: 204}} -> {:ok, container}
      {:ok, %HTTPoison.Response{status_code: 404, body: message}} -> {:error, message}
      {:error, %HTTPoison.Error{reason: reason}} -> {:error, reason}
    end

    {:reply, result, state}
  end

  def handle_call({:delete_container, %Dockex.Container{id: id}}, _from, state) do
    result = case delete("/containers/#{id}", state) do
      {:ok, %HTTPoison.Response{status_code: 204}} -> {:ok, ""}
      {:ok, %HTTPoison.Response{status_code: 404, body: message}} -> {:error, message}
      {:error, %HTTPoison.Error{reason: reason}} -> {:error, reason}
    end

    {:reply, result, state}
  end

  defp get(path, state), do: get(path, state, [])
  defp get(path, state, options), do: request(:get, path, state, "", options)

  defp post(path, state, body), do: post(path, state, body, [])
  defp post(path, state, body, options), do: request(:post, path, state, body, options)

  defp delete(path, state), do: delete(path, state, [])
  defp delete(path, state, options), do: request(:delete, path, state, "", options)

  defp request(method, path, state, body, options) do
    url     = state.config.base_url <> path
    headers = [{"Content-Type", "application/json"}]
    options = options
    |> Keyword.merge([
      hackney: [
        ssl_options: [
          certfile: state.config.ssl_certificate,
          keyfile: state.config.ssl_key
        ]
      ]
    ])

    HTTPoison.request(method, url, body, headers, options)
  end

end
