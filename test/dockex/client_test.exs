defmodule Dockex.Client.Test do
  use ExUnit.Case
  use ExVCR.Mock, adapter: ExVCR.Adapter.Hackney

  alias Dockex.Client

  @container_config %{
    "Env" => nil,
    "ExposedPorts" => %{"22/tcp" => %{}},
    "HostConfig" => %{
      "Binds" => [],
      "ExtraHosts" => [],
      "Links" => [],
      "PortBindings" => %{},
      "RestartPolicy" => %{"MaximumRetryCount" => 3, "Name" => "always"},
      "Volumes" => []
    },
    "Image" => "alpine:3.2",
    "Name" => "alpine_amazing_alzheimer"
  }

  @image %{
    "Created" => 1470937613,
    "Id" => "sha256:07a18c0f21ae608cf2e79e050dc7fc632bca19824a8876da084962ba86877d18",
    "Labels" => %{},
    "ParentId" => "",
    "RepoDigests" => nil,
    "RepoTags" => ["ubuntu:16.10", "ubuntu:devel"],
    "Size" => 99900662,
    "VirtualSize" => 99900662
  }

  @filtered_image %{
    "ParentId" => "",
    "RepoDigests" => nil,
    "Created" => 1466711707,
    "Id" => "sha256:4933271a21f1a3eb183cae296ce2f405c8e0852fb4c90eae577b430393d7ef36",
    "Labels" => nil,
    "RepoTags" => ["alpine:3.2"],
    "Size" => 5256501,
    "VirtualSize" => 5256501
  }

  setup_all do
    ExVCR.Config.cassette_library_dir("test/fixtures/vcr_cassettes")

    config = %Dockex.Client.Config{
      base_url: "https://docker.example.dev:2376",
      ssl_certificate: "test/fixtures/certs/cert.pem",
      ssl_key: "test/fixtures/certs/key.pem"
    }


    {:ok, config: config}
  end

  test "ping: success", %{config: config}do
    use_cassette "ping_success" do
      assert {:ok, "OK"} == Client.ping(config)
    end
  end

  test "ping: unreachable", %{config: config}do
    use_cassette "ping_unreachable" do
      assert {:error, "enetunreach"} == Client.ping(config)
    end
  end

  test "info: success", %{config: config}do
    use_cassette "info_success" do
      {:ok, response} = Client.info(config)

      assert response["Name"] == "cc67a3dd"
    end
  end

  test "list containers: success", %{config: config}do
    use_cassette "list_containers_success" do
      {:ok, response} = Client.list_containers(config)

      container = Enum.at(response, 0)
      assert Map.has_key?(container, "Id")
      assert Map.has_key?(container, "Command")
    end
  end

  test "inspect container: success", %{config: config}do
    use_cassette "inspect_container_success" do
      container = "3d95a5a9b3b0d65e4aa646b29ed39a6bc56637d690d30e4cffc885db11c9eb5a"
      {:ok, response} = Client.inspect_container(config, container)

      assert response["Id"] == container
    end
  end

  # FIXME: see TODO in Dockex.Client
  # test "fetch container logs: success", %{config: config}do
  #   use_cassette "fetch_container_logs_success" do
  #     container = %Dockex.Container{id: "3d95a5a9b3b0d65e4aa646b29ed39a6bc56637d690d30e4cffc885db11c9eb5a"}

  #     {:ok, response} = Client.get_container_logs(client, container)
  #     assert response == "Hello world!\n"

  #     {:ok, response} = Client.get_container_logs(client, container, 1)
  #     assert response == "Hello world!\n"
  #   end
  # end

  test "create container: success", %{config: config}do
    use_cassette "create_container_success" do
      {:ok, response} = Client.create_container(config, @container_config)

      assert response.id == "a493c62afbc1062bf24289848c8ddd3c171d56a6d46e246e33ab39c171a6f455"
    end
  end

  test "start container: success", %{config: config}do
    use_cassette "start_container_success" do
      container = "a493c62afbc1062bf24289848c8ddd3c171d56a6d46e246e33ab39c171a6f455"
      {:ok, response} = Client.start_container(config, container)

      assert response == container
    end
  end

  test "create and start container: success", %{config: config}do
    use_cassette "create_and_start_container_success" do
      {:ok, response} = Client.create_and_start_container(config, @container_config)

      assert response == "abe70fd8df01964f6238b34f98d0222b25f99513a4b79d24814be12326fe5c07"
    end
  end

  test "stop container: success", %{config: config}do
    use_cassette "stop_container_success" do
      container = "a493c62afbc1062bf24289848c8ddd3c171d56a6d46e246e33ab39c171a6f455"
      {:ok, response} = Client.stop_container(config, container, 5)

      assert response == container
    end
  end

  test "restart container: success", %{config: config}do
    use_cassette "restart_container_success" do
      container = "a493c62afbc1062bf24289848c8ddd3c171d56a6d46e246e33ab39c171a6f455"
      {:ok, response} = Client.restart_container(config, container, 5)

      assert response == container
    end
  end

    test "commit container: success", %{config: config}do
      use_cassette "commit_container_success" do
        container = "a493c62afbc1062bf24289848c8ddd3c171d56a6d46e246e33ab39c171a6f455"
        {:ok, response} = Client.commit_container(config, container, "dockex", "latest")

        assert response == %{"Id" => container }
      end
    end

  test "delete container: success", %{config: config}do
    use_cassette "delete_container_success" do
      container = "a493c62afbc1062bf24289848c8ddd3c171d56a6d46e246e33ab39c171a6f455"
      {:ok, response} = Client.delete_container(config, container)

      assert response == "a493c62afbc1062bf24289848c8ddd3c171d56a6d46e246e33ab39c171a6f455"
    end
  end

  test "update container: success", %{config: config}do
    use_cassette "update_container_success" do
      container = "a493c62afbc1062bf24289848c8ddd3c171d56a6d46e246e33ab39c171a6f455"
      update_hash = %{"RestartPolicy" => %{ "MaximumRetryCount" => 4, "Name" => "on-failure" } }
      {:ok, _response} = Client.update_container(config, container, update_hash)
    end
  end

  test "list images: success", %{config: config}do
    use_cassette "list_images_success" do
      {:ok, response} = Client.list_images(config)

      assert response |> Enum.count == 28
      assert response |> Enum.at(0) == @image
    end
  end

  test "list images by name: success", %{config: config}do
    use_cassette "list_images_by_name_success" do
      {:ok, response} = Client.list_images(config, "alpine:3.2")

      assert response |> Enum.count == 1
      assert response |> Enum.at(0) == @filtered_image
    end
  end

  test "image present: success", %{config: config}do
    use_cassette "image_present_success" do
      assert Client.image_present?(config, "alpine:3.2") == true
    end
  end

#  test "pull image: success", %{config: config}do
#    use_cassette "pull_image_success" do
#      {:ok, response} = Client.pull_image(config, "alpine:3.2")
#
#      assert response == "Pulled image alpine:3.2"
#    end
#  end
end
