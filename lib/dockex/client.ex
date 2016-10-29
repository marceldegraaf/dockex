defmodule Dockex.Client do
  use GenServer

  defmodule Config do
    defstruct base_url: nil, ssl_certificate: nil, ssl_key: nil
  end

  defmodule AsyncReply do
    defstruct event: nil, payload: nil, topic: nil
  end

  defmodule AsyncEnd do
    defstruct event: nil, payload: nil, topic: nil
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
  @spec list_containers(pid, boolean) :: {:ok, list(map)} | {:error, String.t}
  def list_containers(pid, all), do: GenServer.call(pid, {:list_containers, all})
  def list_containers(pid), do: list_containers(pid, false)

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

  def stream_logs(pid, identifier, number, target_pid) do
    GenServer.call(pid, {:stream_logs, identifier, number, target_pid})
  end

  @doc """
  Create a container from a map. This map represents the Docker configuration
  that is posted to the Docker API in JSON format. E.g.:

    %{
      "Name": "mysql_amazing_alzheimer",
      "Image": "alpine:3.2",
      "HostConfig": %{ ... },
      "PortBindings": %{ ... },
      "Volumes": [ ... ],
      ...
    }
  """
  @spec create_container(pid, map) :: {:ok, map} | {:error, String.t}
  def create_container(pid, %{} = config) do
    GenServer.call(pid, {:create_container, config})
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
  @spec create_and_start_container(pid, map) :: {:ok, struct} | {:error, String.t}
  def create_and_start_container(pid, %{} = config) do
    with \
      {:ok, container} <- create_container(pid, config), \
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
  def restart_container(pid, identifier, timeout) when is_binary(identifier) do
    GenServer.call(pid, {:restart_container, identifier, timeout})
  end
  def restart_container(pid, %Dockex.Container{id: id}), do: restart_container(pid, id, nil)

  @doc """
  Delete a container.
  """
  @spec delete_container(pid, String.t, boolean) :: {:ok, String.t} | {:error, String.t}
  def delete_container(pid, identifier, force) when is_binary(identifier) do
    GenServer.call(pid, {:delete_container, identifier, force})
  end
  def delete_container(pid, %Dockex.Container{id: id}, force), do: delete_container(pid, id, force)
  def delete_container(pid, identifier) when is_binary(identifier), do: delete_container(pid, identifier, false)
  def delete_container(pid, %Dockex.Container{id: id}), do: delete_container(pid, id, false)

  @doc """
  Commit a container. Returns {:ok, %{"Id": "596069db4bf5"}} when successfull.
  """
  @spec commit_container(pid, String.t, String.t, String.t) :: {:ok, Map.t} | {:error, String.t}
  def commit_container(pid, identifier, repo_name, tag_name) when is_binary(identifier) do
    GenServer.call(pid, {:commit_container, identifier, repo_name, tag_name})
  end
  def commit_container(pid, %Dockex.Container{id: id}, repo_name, tag_name), do: commit_container(pid, id, repo_name, tag_name)

  @doc """
  Update a container. Returns {:ok, ""} when successfull.
  """
  @spec update_container(pid, String.t, Map.t) :: {:ok, Map.t} | {:error, String.t}
  def update_container(pid, identifier, update_map) when is_binary(identifier) do
    GenServer.call(pid, {:update_container, identifier, update_map})
  end
  def update_container(pid, %Dockex.Container{id: id}, update_map), do: update_container(pid, id, update_map)

  @doc """
  List available Docker images on the server.
  """
  @spec list_images(pid) :: {:ok, list(String.t)} | {:error, String.t}
  def list_images(pid), do: GenServer.call(pid, {:list_images, ""})

  @doc """
  List Docker images on the server whose name is `name`.
  """
  @spec list_images(pid, String.t) :: {:ok, list(String.t)} | {:error, String.t}
  def list_images(pid, name), do: GenServer.call(pid, {:list_images, name})

  @doc """
  Test if a Docker image is present on the server.
  """
  @spec image_present?(pid, String.t) :: {:ok, boolean} | {:error, String.t}
  def image_present?(pid, name) do
    {:ok, images} = list_images(pid, name)

    images |> Enum.count > 0
  end

  @doc """
  Pull a Docker image.
  """
  @spec pull_image(pid, String.t) :: {:ok, String.t} | {:error, String.t}
  def pull_image(pid, name) do
    GenServer.call(pid, {:pull_image, name})
  end

  @doc """
  Execute a command inside a running Docker container.
  This is a synchronous operation.
  """
  def exec(pid, %Dockex.Container{id: id}, command), do: exec(pid, id, command)
  def exec(pid, identifier, command) do
    GenServer.call(pid, {:exec, identifier, command})
  end

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

  def handle_call({:list_containers, all}, _from, state) do
    result = get("/containers/json", state, params: %{all: all}) |> handle_docker_json_response
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

  def handle_call({:create_container, %{} = config}, _from, state) do
    {name, config} = config |> Map.pop("Name")
    {:ok, body} = config |> Poison.encode

    result = case post("/containers/create", state, body, params: %{name: name}) do
      {:ok, %HTTPoison.Response{status_code: 201, body: body}} ->
        {:ok, body} = Poison.decode(body)
        {:ok, %Dockex.Container{id: body["Id"]}}

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
    result = post("/containers/#{identifier}/start", state, "") |> handle_docker_response(identifier)
    {:reply, result, state}
  end

  def handle_call({:stop_container, identifier, timeout}, _from, state) do
    result = post("/containers/#{identifier}/stop", state, "", params: %{t: timeout}) |> handle_docker_response(identifier)
    {:reply, result, state}
  end

  def handle_call({:restart_container, identifier, timeout}, _from, state) do
    result = post("/containers/#{identifier}/restart", state, "", params: %{t: timeout}) |> handle_docker_response(identifier)
    {:reply, result, state}
  end

  def handle_call({:delete_container, identifier, force}, _from, state) do
    result = delete("/containers/#{identifier}", state, params: %{force: force}) |> handle_docker_response(identifier)
    {:reply, result, state}
  end

  def handle_call({:commit_container, identifier, repo, tag}, _from, state) do
    result = post("/commit", state, "", params: %{container: identifier, repo: repo, tag: tag}) |> handle_docker_json_response
    {:reply, result, state}
  end

  def handle_call({:update_container, identifier, update_map}, _from, state) do
    {:ok, body} = update_map |> Poison.encode
    result = post("/containers/#{identifier}/update", state, body) |> handle_docker_json_response
    {:reply, result, state}
  end

  def handle_call({:stream_logs, identifier, number, target_pid}, _from, state) do
    task = Task.async(fn -> start_receiving(identifier, target_pid) end)
    result = request(:get, "/containers/#{identifier}/logs", state, "", [
      {:params, %{stdout: 1, stderr: 1, follow: 1, details: 0, timestamps: 0, tail: number}}, {:stream_to, task.pid}
    ])

    # TODO: monitor task

    {:reply, result, state}
  end

  # TODO: add support for streaming output. The Docker API streams JSON messages
  # with pull progess while pulling. HTTPoison has a `stream_to` option that accepts
  # a PID where streamed responses will be sent.
  #
  # See:
  #   - https://github.com/edgurgel/httpoison/blob/master/lib/httpoison/base.ex#L127
  #   - https://docs.docker.com/engine/reference/api/docker_remote_api_v1.24/#/create-an-image
  def handle_call({:pull_image, name}, _from, state) do
    result = case post("/images/create", state, "", params: %{fromImage: name}) do
      {:ok, %HTTPoison.Response{status_code: 200}} -> {:ok, "Pulled image #{name}"}
      {:error, %HTTPoison.Error{reason: reason}} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end

    {:reply, result, state}
  end

  def handle_call({:list_images, name}, _from, state) do
    result = case get("/images/json", state, params: %{filter: name}) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} -> Poison.decode(body)
      {:error, %HTTPoison.Error{reason: reason}} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end

    {:reply, result, state}
  end

  def handle_call({:exec, identifier, command}, _from, state) do
    # Prepare exec create params
    {:ok, json} = %{"AttachStdin" => false, "AttachStdout" => true, "AttachStderr" => true, "Tty" => true, "Cmd" => [command]}
    |> Poison.encode

    # Create a new exec instance and get the ID of the exec
    {:ok, %HTTPoison.Response{status_code: 201, body: body}} = post("/containers/#{identifier}/exec", state, json)
    {:ok, response} = body |> Poison.decode
    id = response["Id"]

    # Prepare exec start params
    {:ok, json} = %{"Detach" => false, "Tty" => false}
    |> Poison.encode

    task = Task.async(fn -> receive_exec_stream() end)

    # Start the exec
    case request(:post, "/exec/#{id}/start", state, json, [{:stream_to, task.pid}]) do
       response -> IO.puts("#{inspect response}")
    end

    # Inspect the exec
    result = case get("/exec/#{id}/json", state) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} -> Poison.decode(body)
      {:error, %HTTPoison.Error{reason: reason}} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end

    {:reply, result, state}
  end

  def receive_exec_stream do
    receive do
      %HTTPoison.AsyncChunk{chunk: chunk} ->
        IO.puts("EXEC RECEIVE: #{chunk}")
        receive_exec_stream

      %HTTPoison.AsyncEnd{} ->
        IO.puts("EXEC RECEIVE: stream ended")

      :close ->
        IO.puts("EXEC RECEIVE: stream closed")
    end
  end

  def start_receiving(identifier, target_pid) do
    receive do
      %HTTPoison.AsyncChunk{chunk: new_data} ->
        send target_pid, %Dockex.Client.AsyncReply{event: "receive_data", payload: new_data, topic: identifier}
        start_receiving(identifier, target_pid)

      %HTTPoison.AsyncEnd{} ->
        send target_pid, %Dockex.Client.AsyncEnd{event: "stream_end", topic: identifier}

      :close ->
        send target_pid, %Dockex.Client.AsyncEnd{event: "stream_closed", topic: identifier}
    end
  end

  defp get(path, state), do: get(path, state, [])
  defp get(path, state, options), do: request(:get, path, state, "", options)

  defp post(path, state, body), do: post(path, state, body, [])
  defp post(path, state, body, options), do: request(:post, path, state, body, options)

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
      {:ok, %HTTPoison.Response{status_code: 404, body: body}} -> {:error, body}
      {:ok, %HTTPoison.Response{status_code: code, body: body}} -> {:error, "#{code}: #{body}"}
      {:error, %HTTPoison.Error{reason: reason}} -> {:error, reason}
      {_, reason} -> {:error, reason}
    end
  end

  defp handle_docker_response(result_tuple, identifier) do
    case handle_docker_response(result_tuple) do
      {:ok, ""} -> {:ok, identifier}
      {key, value} -> {key, value}
    end
  end

  defp handle_docker_json_response(result_tuple) do
    case handle_docker_response(result_tuple) do
      {:ok, body} -> Poison.decode(body)
      {:error, error_message} -> {:error, error_message}
    end
  end

end
