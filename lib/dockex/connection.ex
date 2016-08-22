defmodule Dockex.Connection do
  defstruct hostname: nil, port: nil, ssl_certificate: nil, ssl_private_key: nil

  def start_link(%Dockex.Connection{} = config), do: Agent.start_link(fn -> config end, name: __MODULE__)

  def get, do: Agent.get(__MODULE__, fn(state) -> state end)
end
