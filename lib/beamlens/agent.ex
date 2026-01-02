defmodule Beamlens.Agent do
  @moduledoc """
  BAML-based agent that analyzes BEAM health.

  Uses Claude Haiku via BAML to interpret VM metrics and provide
  structured health assessments with type-safe outputs.
  """

  require Logger

  alias Beamlens.Baml.AnalyzeBeamHealth
  alias Beamlens.Baml.BeamMetrics
  alias Beamlens.Baml.MemoryStats

  @doc """
  Run a health analysis.

  Collects current BEAM metrics and sends them to Claude Haiku
  for analysis. Returns a structured `HealthReport`.

  ## Options

    * `:stream` - If true, streams partial results (default: false)

  ## Examples

      {:ok, report} = Beamlens.Agent.run()
      report.status
      #=> "healthy"
      report.summary
      #=> "BEAM VM is operating normally with healthy memory usage..."
      report.concerns
      #=> []
  """
  def run(_opts \\ []) do
    metrics = collect_metrics()

    case AnalyzeBeamHealth.call(%{metrics: metrics}, %{}) do
      {:ok, report} ->
        {:ok, report}

      {:error, reason} = error ->
        Logger.warning("[BeamLens] Agent failed: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Run analysis with streaming partial results.

  Calls the provided callback with partial results as they stream in.

  ## Examples

      {:ok, report} = Beamlens.Agent.run_stream(fn partial ->
        IO.puts("Partial: \#{inspect(partial)}")
      end)
  """
  def run_stream(callback, _opts \\ []) do
    metrics = collect_metrics()

    AnalyzeBeamHealth.sync_stream(%{metrics: metrics}, callback, %{})
  end

  # Collect metrics and convert to BAML struct format
  defp collect_metrics do
    raw = Beamlens.Collector.beam_metrics()

    %BeamMetrics{
      node: raw.node,
      otp_release: raw.otp_release,
      schedulers_online: raw.schedulers_online,
      memory: %MemoryStats{
        total_mb: raw.memory.total_mb,
        processes_mb: raw.memory.processes_mb,
        atom_mb: raw.memory.atom_mb,
        binary_mb: raw.memory.binary_mb,
        ets_mb: raw.memory.ets_mb
      },
      process_count: raw.process_count,
      port_count: raw.port_count,
      uptime_seconds: raw.uptime_seconds,
      run_queue: raw.run_queue
    }
  end
end
