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
      # TODO: Switch back to hex.pm once ClientRegistry is released
      # {:baml_elixir, "~> 1.0.0-pre.24"},
      {:baml_elixir,
       github: "emilsoman/baml_elixir",
       ref: "51fdb81640230dd14b4556c1d078bce8d8218368",
       override: true},
      {:rustler, "~> 0.36", optional: true},
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
