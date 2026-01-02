defmodule Beamlens.MixProject do
  use Mix.Project

  def project do
    [
      app: :beamlens,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "A minimal AI agent that monitors BEAM VM health",
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Beamlens.Application, []}
    ]
  end

  defp deps do
    [
      {:strider, github: "bradleygolden/strider", ref: "28c077c"},
      {:jason, "~> 1.4"},
      {:zoi, "~> 0.12"},
      {:baml_elixir, "~> 1.0.0-pre.23"},
      {:telemetry, "~> 1.2"}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{}
    ]
  end
end
