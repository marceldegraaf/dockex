defmodule Dockex.Client.Test do
  use ExUnit.Case
  use ExVCR.Mock, adapter: ExVCR.Adapter.Hackney

  alias Dockex.Client

  setup_all do
    ExVCR.Config.cassette_library_dir("test/fixtures/vcr_cassettes")

    config = %Dockex.Client.Config{
      base_url: "https://docker.example.dev:2376",
      ssl_certificate: "test/fixtures/certs/cert.pem",
      ssl_key: "test/fixtures/certs/key.pem"
    }

    {:ok, pid} = Dockex.Client.start_link(config)

    {:ok, state: %{config: config}, client: pid}
  end

  test "ping: success", %{client: client} do
    use_cassette "ping_success" do
      assert {:ok, "OK"} == Client.ping(client)
    end
  end

  test "ping: unreachable", %{client: client} do
    use_cassette "ping_unreachable" do
      assert {:error, "enetunreach"} == Client.ping(client)
    end
  end

  test "info: success", %{client: client} do
    use_cassette "info_success" do
      {:ok, response} = Client.info(client)

      assert response["Name"] == "cc67a3dd"
    end
  end

  test "list containers: success", %{client: client} do
    use_cassette "list_containers_success" do
      {:ok, response} = Client.list_containers(client)

      container = Enum.at(response, 0)
      assert Map.has_key?(container, "Id")
      assert Map.has_key?(container, "Command")
    end
  end

  test "inspect container: success", %{client: client} do
    use_cassette "inspect_container_success" do
      container = %Dockex.Container{id: "3d95a5a9b3b0d65e4aa646b29ed39a6bc56637d690d30e4cffc885db11c9eb5a"}
      {:ok, response} = Client.inspect_container(client, container)

      assert response["Id"] == container.id
    end
  end

  # FIXME: see TODO in Dockex.Client
  # test "fetch container logs: success", %{client: client} do
  #   use_cassette "fetch_container_logs_success" do
  #     container = %Dockex.Container{id: "3d95a5a9b3b0d65e4aa646b29ed39a6bc56637d690d30e4cffc885db11c9eb5a"}

  #     {:ok, response} = Client.get_container_logs(client, container)
  #     assert response == "Hello world!\n"

  #     {:ok, response} = Client.get_container_logs(client, container, 1)
  #     assert response == "Hello world!\n"
  #   end
  # end

  test "create container: success", %{client: client} do
    use_cassette "create_container_success" do
      container = %Dockex.Container{name: "test", image: "alpine:3.2", cmd: ["/bin/echo", "hi!"]}
      {:ok, response} = Client.create_container(client, container)

      assert response.id == "a493c62afbc1062bf24289848c8ddd3c171d56a6d46e246e33ab39c171a6f455"
    end
  end

  test "start container: success", %{client: client} do
    use_cassette "start_container_success" do
      container = %Dockex.Container{id: "a493c62afbc1062bf24289848c8ddd3c171d56a6d46e246e33ab39c171a6f455"}
      {:ok, response} = Client.start_container(client, container)

      assert response.id == container.id
    end
  end

  test "create and start container: success", %{client: client} do
    use_cassette "create_and_start_container_success" do
      container = %Dockex.Container{cmd: ["/bin/echo", "hi!"], image: "alpine:3.2", name: "test_2"}
      {:ok, response} = Client.create_and_start_container(client, container)

      assert response.id == "abe70fd8df01964f6238b34f98d0222b25f99513a4b79d24814be12326fe5c07"
    end
  end

  test "stop container: success", %{client: client} do
    use_cassette "stop_container_success" do
      container = %Dockex.Container{id: "a493c62afbc1062bf24289848c8ddd3c171d56a6d46e246e33ab39c171a6f455"}
      {:ok, response} = Client.stop_container(client, container, 5)

      assert response.id == container.id
    end
  end

  test "restart container: success", %{client: client} do
    use_cassette "restart_container_success" do
      container = %Dockex.Container{id: "a493c62afbc1062bf24289848c8ddd3c171d56a6d46e246e33ab39c171a6f455"}
      {:ok, response} = Client.restart_container(client, container, 5)

      assert response.id == container.id
    end
  end

  test "delete container: success", %{client: client} do
    use_cassette "delete_container_success" do
      container = %Dockex.Container{id: "a493c62afbc1062bf24289848c8ddd3c171d56a6d46e246e33ab39c171a6f455"}
      {:ok, response} = Client.delete_container(client, container)

      assert response == ""
    end
  end
end
