defmodule Beamlens.Runner do
  @moduledoc """
  Periodic runner for BeamLens health checks.

  Runs the agent at configurable intervals and logs results.
  """

  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    interval = opts[:interval] || :timer.minutes(5)
    mode = opts[:mode] || :periodic

    state = %{
      interval: interval,
      mode: mode,
      last_report: nil,
      last_run_at: nil
    }

    if mode != :manual do
      # Run first check after a short delay to let the app stabilize
      schedule_run(5_000)
    end

    {:ok, state}
  end

  @impl true
  def handle_call(:last_report, _from, state) do
    {:reply, {:ok, state.last_report}, state}
  end

  @impl true
  def handle_info(:run, state) do
    node = Atom.to_string(Node.self())

    {_result, new_state} =
      Beamlens.Telemetry.span(%{node: node}, fn ->
        case Beamlens.Agent.run() do
          {:ok, report} ->
            Logger.info("[BeamLens] Health Report: #{report.status}")

            metadata = %{
              node: node,
              status: Beamlens.Telemetry.status_from_report(report),
              report: report
            }

            new_state = %{state | last_report: report, last_run_at: DateTime.utc_now()}
            {{{:ok, report}, new_state}, %{}, metadata}

          {:error, reason} ->
            Logger.warning("[BeamLens] Agent failed: #{inspect(reason)}")
            {{{:error, reason}, state}, %{}, %{node: node, error: reason}}
        end
      end)

    schedule_run(state.interval)
    {:noreply, new_state}
  end

  defp schedule_run(interval) do
    Process.send_after(self(), :run, interval)
  end
end
