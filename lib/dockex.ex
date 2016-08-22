defmodule Dockex do
  use Application

  def start(_type, _args) do
    import Supervisor.Spec

    children = [
      worker(Dockex.Connection, []),
    ]

    Supervisor.start_link(children, strategy: :simple_one_for_one, name: __MODULE__)
  end
end
