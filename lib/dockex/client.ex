defmodule Dockex.Client do
  use GenServer

  defmodule Config do
    defstruct base_url: nil, ssl_certificate: nil, ssl_key: nil
  end

  def start_link(%Dockex.Client.Config{} = config) do
    GenServer.start_link(__MODULE__, config)
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
  Inspect a container. Accepts an id, a name or a `%Dockex.Container{}` struct to specify
  which container to inspect.
  """
  @spec inspect_container(pid, String.t) :: {:ok, map} | {:error, String.t}
  def inspect_container(pid, identifier) when is_binary(identifier) do
    GenServer.call(pid, {:inspect_container, identifier})
  end
  def inspect_container(pid, %Dockex.Container{id: id}), do: inspect_container(pid, id)

  @doc """
  Fetch the last `number` lines of container logs.
  """
  @spec get_container_logs(pid, String.t, number) :: {:ok, String.t} | {:error, String.t}
  def get_container_logs(pid, identifier, number) when is_binary(identifier) do
    GenServer.call(pid, {:get_container_logs, identifier, number})
  end
  def get_container_logs(pid, %Dockex.Container{id: id}), do: get_container_logs(pid, id, 50)

  def stream_logs(pid, identifier, number) do
    GenServer.cast(pid, {:stream_logs, identifier, number})
  end

  @doc """
  Create a container.
  """
  @spec create_container(pid, String.t) :: {:ok, struct} | {:error, String.t}
  def create_container(pid, %Dockex.Container{} = container) do
    GenServer.call(pid, {:create_container, container})
  end

  @doc """
  Start a previously created container.
  """
  @spec start_container(pid, String.t) :: {:ok, struct} | {:error, String.t}
  def start_container(pid, identifier) when is_binary(identifier) do
    GenServer.call(pid, {:start_container, identifier})
  end
  def start_container(pid, %Dockex.Container{id: id}), do: start_container(pid, id)

  @doc """
  Create and start a container at the same time.
  """
  @spec create_and_start_container(pid, %Dockex.Container{}) :: {:ok, struct} | {:error, String.t}
  def create_and_start_container(pid, %Dockex.Container{} = container) do
    with \
      {:ok, container} <- create_container(pid, container), \
      {:ok, container} <- start_container(pid, container) \
    do \
      {:ok, container}
    end
  end


  @doc """
  Stop a running container.
  """
  @spec stop_container(pid, String.t, number) :: {:ok, struct} | {:error, String.t}
  def stop_container(pid, identifier, timeout) when is_binary(identifier) do
    GenServer.call(pid, {:stop_container, identifier, timeout})
  end
  def stop_container(pid, %Dockex.Container{id: id}), do: stop_container(pid, id, nil)

  @doc """
  Restart a running container.
  """
  @spec restart_container(pid, String.t, number) :: {:ok, struct} | {:error, String.t}
  def restart_container(pid, identifier, timeout) do
    GenServer.call(pid, {:restart_container, identifier, timeout})
  end
  def restart_container(pid, %Dockex.Container{id: id}), do: restart_container(pid, id, nil)

  @doc """
  Delete a container.
  """
  @spec delete_container(pid, String.t) :: {:ok, String.t} | {:error, String.t}
  def delete_container(pid, identifier) when is_binary(identifier) do
    GenServer.call(pid, {:delete_container, identifier})
  end
  def delete_container(pid, %Dockex.Container{id: id}), do: delete_container(pid, id)

  #
  # GenServer callbacks
  #

  def handle_call(:ping, _from, state) do
    result = get("/_ping", state) |> handle_docker_response
    {:reply, result, state}
  end

  def handle_call(:info, _from, state) do
    result = get("/info", state) |> handle_docker_json_response
    {:reply, result, state}
  end

  def handle_call(:list_containers, _from, state) do
    result = get("/containers/json", state) |> handle_docker_json_response
    {:reply, result, state}
  end

  def handle_call({:inspect_container, identifier}, _from, state) do
    result = get("/containers/#{identifier}/json", state) |> handle_docker_json_response
    {:reply, result, state}
  end

  # TODO This works:
  #
  #   Dockex.Client.get_container_logs(client, identifier, 1)
  #
  # But this still returns an unparsed bitstring:
  #
  #   Dockex.Client.get_container_logs(client, identifier, 2)
  #
  # Probably because each new line starts with the same <<type, 0, 0, 0, _size ... >> information?
  #
  def handle_call({:get_container_logs, identifier, number}, _from, state) do
    result = case get("/containers/#{identifier}/logs", state, params: %{stdout: 1, tail: number}) do
      {:ok, %HTTPoison.Response{status_code: 200, body: ""}} ->
        {:ok, ""}

      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        <<type, 0, 0, 0, _size :: integer-big-size(32), output :: binary>> = body
        {:ok, output}

      {:ok, %HTTPoison.Response{status_code: 404, body: message}} ->
        {:error, message}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, reason}

      {:error, reason} -> {:error, reason}
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

      {:error, reason} -> {:error, reason}
    end

    {:reply, result, state}
  end

  def handle_call({:start_container, identifier}, _from, state) do
    result = post("/containers/#{identifier}/start", state, "") |> handle_docker_response
    {:reply, result, state}
  end

  def handle_call({:stop_container, identifier, timeout}, _from, state) do
    result = post("/containers/#{identifier}/stop", state, "", params: %{t: timeout}) |> handle_docker_response
    {:reply, result, state}
  end

  def handle_call({:restart_container, identifier, timeout}, _from, state) do
    result = post("/containers/#{identifier}/restart", state, "", params: %{t: timeout}) |> handle_docker_response
    {:reply, result, state}
  end

  def handle_call({:delete_container, identifier}, _from, state) do
    result = delete("/containers/#{identifier}", state) |> handle_docker_response
    {:reply, result, state}
  end


  def handle_cast({:stream_logs, identifier, number}, state) do
    task = Task.async(fn -> start_receiving(identifier) end)
    request = request(:get, "/containers/#{identifier}/logs", state, "", [{:params, %{stdout: 1, stderr: 1, follow: 1, details: 1, timestamps: 1, tail: number}}, {:stream_to, task.pid}])
    {:noreply, state}
  end

  def start_receiving(identifier) do
    receive do

      %HTTPoison.AsyncChunk{chunk: new_data} ->
        IO.inspect("#{identifier}:#{new_data}")
        start_receiving(identifier)

      %HTTPoison.AsyncEnd{} ->
        IO.inspect("#{identifier}: STREAM ENDED")

      :close ->
        IO.inspect("#{identifier}: STREAM CLOSED")

    end
  end

  defp get(path, state), do: get(path, state, [])
  defp get(path, state, options), do: request(:get, path, state, "", options)

  defp post(path, state, body), do: post(path, state, body, [])
  defp post(path, state, body, options), do: request(:post, path, state, body, options)

  defp delete(path, state), do: delete(path, state, [])
  defp delete(path, state, options), do: request(:delete, path, state, "", options)

  defp request(_, _, %{config: %{base_url: nil}}, _, _), do: {:error, "Dockex is not configured"}
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

  defp handle_docker_response(result_tuple) do
    case result_tuple do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} -> {:ok ,body}
      {:ok, %HTTPoison.Response{status_code: 201, body: body}} -> {:ok, body}
      {:ok, %HTTPoison.Response{status_code: 204, body: body}} -> {:ok, body}
      {:ok, %HTTPoison.Response{status_code: 304, body: body}} -> {:ok, body}
      {:ok, %HTTPoison.Response{status_code: result_code, body: body}} -> {:error, result_code <> "" <> body}
      {:error, %HTTPoison.Error{reason: reason}} -> {:error, reason}
      {_, reason} -> {:error, reason}
    end
  end

  defp handle_docker_json_response(result_tuple) do
    case handle_docker_response(result_tuple) do
      {:ok, body} -> {:ok, Poison.decode(body)}
      {:error, error_message} -> {:error, error_message}
    end
  end

end
