defmodule Beamlens do
  @moduledoc """
  BeamLens - A minimal AI agent that monitors BEAM VM health.

  Periodically analyzes BEAM metrics and generates health analyses
  using Claude Haiku. Safe by design: read-only, no PII/PHI exposure.

  ## Usage

      # Add to your application supervision tree
      {Beamlens, []}

      # Or run manually
      {:ok, analysis} = Beamlens.run()

  ## Configuration

      # Environment variable (required by BAML)
      export ANTHROPIC_API_KEY=your-api-key

      # Elixir config
      config :beamlens,
        mode: :periodic,
        interval: :timer.minutes(5)
  """

  @doc """
  Manually trigger a health analysis.

  Returns `{:ok, analysis}` where analysis is the AI-generated health assessment.
  """
  defdelegate run(opts \\ []), to: Beamlens.Agent

  @doc """
  Returns a child spec for adding Beamlens to a supervision tree.
  """
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {Beamlens.Runner, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end
end
