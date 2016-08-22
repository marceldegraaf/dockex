defmodule Dockex.Mixfile do
  use Mix.Project

  def project do
    [
      app: :dockex,
      version: "0.1.0",
      elixir: "~> 1.3",
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      applications: [:logger, :httpoison],
      mod: {Dockex, []},
    ]
  end

  defp deps do
    [
      {:httpoison, "> 0.0.0"},
      {:poison, "> 0.0.0"},
      {:earmark, "> 0.0.0", only: :dev},
      {:ex_doc, "> 0.0.0", only: :dev},
    ]
  end
end
