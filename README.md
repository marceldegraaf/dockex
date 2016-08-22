# Dockex

**Note:** this library is to be considered unstable as long as this message is
here.

Dockex is a Docker client for Elixir. It uses HTTPoison (and thus, hackney) to
communicate with Docker's HTTPS endpoint.

## Usage

Create a `Dockex.Client.Config` struct with your Docker server's connection
configuration:

    config = %Dockex.Client.Config{
      base_url:        "https://your-docker-server-host:2376",
      ssl_certificate: "/path/to/docker/cert.pem",
      ssl_key:         "/path/to/docker/key.pem",
    }

Start the client:

    {:ok, pid} = Dockex.Client.start_link(config)

And use it:

    # Ping the Docker server
    {:ok, ""} = Dockex.Client.ping(pid)

    # List all running containers
    {:ok, [...]} = Dockex.Client.list_containers(pid)

    # Initialize a container struct
    container = %Dockex.Container{
      name: "foobar",
      cmd: ["/bin/sh", "-c", "echo 'hi there'"],
      image: "alpine:3.2"
    }

    # Create and start a new container
    {:ok, container} = Dockex.Client.create_and_start_container(pid, container)

    # Fetch logs for a container
    {:ok, output} = Dockex.Client.get_container_logs(pid, container)

    # Stop a container
    {:ok, container} = Dockex.Client.stop_container(pid, container)

    # Delete a container
    {:ok, ""} = Dockex.Client.delete_container(pid, container)
