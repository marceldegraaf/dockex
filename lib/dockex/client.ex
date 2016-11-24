defmodule Dockex.Client do
  defmodule Config do
    defstruct base_url: nil, ssl_certificate: nil, ssl_key: nil
  end

  defmodule AsyncReply do
    defstruct event: nil, payload: nil, topic: nil
  end

  defmodule AsyncEnd do
    defstruct event: nil, payload: nil, topic: nil
  end

  @doc """
  Ping the Docker server to check if it's up and if the connection
  configuration is correct.
  """
  @spec ping(%Dockex.Client.Config{}) :: {:ok, String.t} | {:error, String.t}
  def ping(config) do
    get(config, "/_ping") |> handle_docker_response
  end

  @doc """
  Query the Docker server for runtime information.
  """
  @spec info(%Dockex.Client.Config{}) :: {:ok, map} | {:error, String.t}
  def info(config) do
    get(config, "/info") |> handle_docker_json_response
  end

  @doc """
  List running containers.
  """
  @spec list_containers(%Dockex.Client.Config{}, boolean) :: {:ok, list(map)} | {:error, String.t}
  def list_containers(config, all) do
    get(config, "/containers/json", params: %{all: all}) |> handle_docker_json_response
  end

  def list_containers(config), do: list_containers(config, false)

  @doc """
  Inspect a container. Accepts an id, a name or a `%Dockex.Container{}` struct to specify
  which container to inspect.
  """
  @spec inspect_container(%Dockex.Client.Config{}, String.t) :: {:ok, map} | {:error, String.t}
  def inspect_container(config, identifier) when is_binary(identifier) do
    get(config, "/containers/#{identifier}/json") |> handle_docker_json_response
  end
  def inspect_container(config, %Dockex.Container{id: id}), do: inspect_container(config, id)

  @doc """
  Fetch the last `number` lines of container logs.
  """
  @spec get_container_logs(%Dockex.Client.Config{}, String.t, number) :: {:ok, String.t} | {:error, String.t}
  def get_container_logs(config, identifier, number) when is_binary(identifier) do
    case get(config, "/containers/#{identifier}/logs", params: %{stdout: 1, tail: number}) do
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
  end
  def get_container_logs(config, %Dockex.Container{id: id}), do: get_container_logs(config, id, 50)

  def stream_logs(config, identifier, number, target_pid) do
    task = Task.async(fn -> start_receiving(identifier, target_pid) end)
    request(:get, "/containers/#{identifier}/logs", "", [
        {:params, %{stdout: 1, stderr: 1, follow: 1, details: 0, timestamps: 0, tail: number}}, {:stream_to, task.pid}
    ])

    task
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
  @spec create_container(%Dockex.Client.Config{}, map) :: {:ok, map} | {:error, String.t}
  def create_container(docker_config, %{} = config) do
    {name, config} = config |> Map.pop("Name")
    {:ok, body} = config |> Poison.encode

    case post(docker_config, "/containers/create", body, params: %{name: name}) do
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

  end

  @doc """
  Start a previously created container.
  """
  @spec start_container(%Dockex.Client.Config{}, String.t) :: {:ok, struct} | {:error, String.t}
  def start_container(config, identifier) when is_binary(identifier) do
    post(config, "/containers/#{identifier}/start", "") |> handle_docker_response(identifier)
  end
  def start_container(config, %Dockex.Container{id: id}), do: start_container(config, id)

  @doc """
  Create and start a container at the same time.
  """
  @spec create_and_start_container(%Dockex.Client.Config{}, map) :: {:ok, struct} | {:error, String.t}
  def create_and_start_container(docker_config, %{} = config) do
    with \
      {:ok, container} <- create_container(docker_config, config), \
      {:ok, container} <- start_container(docker_config, container) \
    do \
      {:ok, container}
    end
  end

  @doc """
  Stop a running container.
  """
  @spec stop_container(%Dockex.Client.Config{}, String.t, number) :: {:ok, struct} | {:error, String.t}
  def stop_container(config, identifier, timeout) when is_binary(identifier) do
    post(config, "/containers/#{identifier}/stop", "", params: %{t: timeout}) |> handle_docker_response(identifier)
  end
  def stop_container(config, %Dockex.Container{id: id}), do: stop_container(config, id, nil)

  @doc """
  Restart a running container.
  """
  @spec restart_container(%Dockex.Client.Config{}, String.t, number) :: {:ok, struct} | {:error, String.t}
  def restart_container(config, identifier, timeout) when is_binary(identifier) do
    post(config, "/containers/#{identifier}/restart", "", params: %{t: timeout}) |> handle_docker_response(identifier)
  end
  def restart_container(config, %Dockex.Container{id: id}), do: restart_container(config, id, nil)

  @doc """
  Delete a container.
  """
  @spec delete_container(%Dockex.Client.Config{}, String.t, boolean) :: {:ok, String.t} | {:error, String.t}
  def delete_container(config, identifier, force) when is_binary(identifier) do
    delete(config, "/containers/#{identifier}", params: %{force: force}) |> handle_docker_response(identifier)
  end
  def delete_container(config, %Dockex.Container{id: id}, force), do: delete_container(config, id, force)
  def delete_container(config, identifier) when is_binary(identifier), do: delete_container(config, identifier, false)
  def delete_container(config, %Dockex.Container{id: id}), do: delete_container(config, id, false)

  @doc """
  Commit a container. Returns {:ok, %{"Id": "596069db4bf5"}} when successfull.
  """
  @spec commit_container(%Dockex.Client.Config{}, String.t, String.t, String.t) :: {:ok, Map.t} | {:error, String.t}
  def commit_container(config, identifier, repo_name, tag_name) when is_binary(identifier) do
    post(config, "/commit", "", params: %{container: identifier, repo: repo_name, tag: tag_name}) |> handle_docker_json_response
  end
  def commit_container(config, %Dockex.Container{id: id}, repo_name, tag_name), do: commit_container(config, id, repo_name, tag_name)

  @doc """
  Update a container. Returns {:ok, ""} when successfull.
  """
  @spec update_container(%Dockex.Client.Config{}, String.t, Map.t) :: {:ok, Map.t} | {:error, String.t}
  def update_container(config, identifier, update_map) when is_binary(identifier) do
    {:ok, body} = update_map |> Poison.encode
    post(config, "/containers/#{identifier}/update", body) |> handle_docker_json_response
  end
  def update_container(config, %Dockex.Container{id: id}, update_map), do: update_container(config, id, update_map)

  @doc """
  List available Docker images on the server.
  """
  @spec list_images(%Dockex.Client.Config{}) :: {:ok, list(String.t)} | {:error, String.t}
  def list_images(config, name) do
    case get(config, "/images/json", params: %{filter: name}) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} -> Poison.decode(body)
      {:error, %HTTPoison.Error{reason: reason}} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  List Docker images on the server whose name is `name`.
  """
  @spec list_images(%Dockex.Client.Config{}, String.t) :: {:ok, list(String.t)} | {:error, String.t}
  def list_images(config), do: list_images(config, "")

  @doc """
  Test if a Docker image is present on the server.
  """
  @spec image_present?(%Dockex.Client.Config{}, String.t) :: {:ok, boolean} | {:error, String.t}
  def image_present?(config, name) do
    {:ok, images} = list_images(config, name)

    images |> Enum.count > 0
  end

  @doc """
  Pull a Docker image.
  """
  @spec pull_image(%Dockex.Client.Config{}, String.t) :: {:ok, String.t} | {:error, String.t}
  def pull_image(config, name) do
    case post(config, "/images/create", "", params: %{fromImage: name}) do
      {:ok, %HTTPoison.Response{status_code: 200}} -> {:ok, "Pulled image #{name}"}
      {:error, %HTTPoison.Error{reason: reason}} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Execute a command inside a running Docker container.
  This is a synchronous operation.
  """
  def exec(config, %Dockex.Container{id: id}, command, target_pid) when is_binary(command), do: exec(config, id, command, target_pid)
  def exec(config, identifier, command, target_pid) when is_binary(command), do: exec(config, identifier, String.split(command, " "), target_pid)

  def exec(config, identifier, command, target_pid) when is_list(command) do
    # Prepare exec create params
    {:ok, json} = %{"AttachStdin" => false, "AttachStdout" => true, "AttachStderr" => true, "Tty" => true, "Cmd" => command}
      |> Poison.encode

    # Create a new exec instance and get the ID of the exec
    {:ok, %HTTPoison.Response{status_code: 201, body: body}} = post(config, "/containers/#{identifier}/exec", json)
    {:ok, response} = body |> Poison.decode
    id = response["Id"]

    # Prepare exec start params
    {:ok, json} = %{"Detach" => false, "Tty" => false}
      |> Poison.encode

    task = Task.async(fn -> receive_exec_stream(identifier, target_pid) end)

    # Start the exec
    case request(config, :post, "/exec/#{id}/start", json, [{:stream_to, task.pid}]) do
       response -> IO.puts("#{inspect response}")
    end

    # Inspect the exec
    case get(config, "/exec/#{id}/json") do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} -> Poison.decode(body)
      {:error, %HTTPoison.Error{reason: reason}} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  def receive_exec_stream(identifier, target_pid) do
    receive do
      %HTTPoison.AsyncChunk{chunk: chunk} ->
        payload = case decode_stream(chunk, []) do
          {[], rest} -> rest
          {[stdin: line], _rest} -> line
          {[stdout: line], _rest} -> line
          {[sterr: line], _rest} -> line
        end

        send target_pid, %Dockex.Client.AsyncReply{event: "exec_stream_data", payload: payload, topic: identifier}

        receive_exec_stream(identifier, target_pid)

      %HTTPoison.AsyncEnd{} ->
        send target_pid, %Dockex.Client.AsyncEnd{event: "exec_stream_end", topic: identifier}

      :close ->
        send target_pid, %Dockex.Client.AsyncEnd{event: "exec_stream_end", topic: identifier}
    end
  end

  def decode_stream(<<type, 0 ,0, 0, size :: integer-big-size(32), rest :: binary>> = packet, acc) do
    if size <= byte_size(rest) do
      <<data :: binary-size(size), rest0 :: binary>> = rest

      type = case type do
        0 -> :stdin
        1 -> :stdout
        2 -> :stderr
        other -> other
      end

      acc = [ { type, data } | acc ]

      decode_stream(rest0, acc)
    else
     { Enum.reverse(acc), packet }
    end
  end
  def decode_stream(packet, acc) when byte_size(packet) < 8 do
    { Enum.reverse(acc), packet }
  end
  def decode_stream(_packet, _acc), do: raise ArgumentError

  def start_receiving(identifier, target_pid) do
    receive do
      %HTTPoison.AsyncChunk{chunk: new_data} ->
        send target_pid, %Dockex.Client.AsyncReply{event: "log_stream_data", payload: new_data, topic: identifier}
        start_receiving(identifier, target_pid)

      %HTTPoison.AsyncEnd{} ->
        send target_pid, %Dockex.Client.AsyncEnd{event: "log_stream_end", topic: identifier}

      :close ->
        send target_pid, %Dockex.Client.AsyncEnd{event: "log_stream_end", topic: identifier}
    end
  end

  defp get(config, path), do: get(config, path, [])
  defp get(config, path, options), do: request(config, :get, path, "", options)

  defp post(config, path, body), do: post(config, path, body, [])
  defp post(config, path, body, options), do: request(config, :post, path, body, options)

  defp delete(config, path, options), do: request(config, :delete, path, "", options)

  defp request(%{base_url: nil}, _ , _, _), do: {:error, "Config is not configured"}
  defp request(config, method, path, body, options) do
    url     = config.base_url <> path

    headers = [{"Content-Type", "application/json"}]
    options = options
    |> Keyword.merge([
      hackney: [
        ssl_options: [
          certfile: config.ssl_certificate,
          keyfile: config.ssl_key
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
