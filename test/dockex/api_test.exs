defmodule Dockex.API.Test do
  use ExUnit.Case

  test "process_url callback" do
  end

  test "process_response_body callback" do
    assert Dockex.API.process_response_body("this is the body") == "this is the body"
  end

  test "process_request_headers callback" do
    initial_headers = [{"X-Header-Foo", "value-bar"}]
    headers = initial_headers |> Dockex.API.process_request_headers

    assert headers == [{"Content-Type", "application/json"} | initial_headers]
  end
end
