defmodule Dockex.Config do
  def start_link(config), do: Agent.start_link(fn -> config end, name: __MODULE__)

  def get, do: Agent.get(__MODULE__, fn(state) -> state end)
end
