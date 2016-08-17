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

    {:ok, _pid} = Dockex.Client.start_link(config)

Use the client's functions:

    {:ok, ""} = Dockex.Client.ping

    {:ok, [...]} = Dockex.Client.list_containers

    ...
