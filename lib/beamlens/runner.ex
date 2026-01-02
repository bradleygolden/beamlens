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
    new_state =
      case Beamlens.Agent.run() do
        {:ok, report} ->
          Logger.info("[BeamLens] Health Report:\n#{report}")

          %{
            state
            | last_report: report,
              last_run_at: DateTime.utc_now()
          }

        {:error, reason} ->
          Logger.warning("[BeamLens] Health check failed: #{inspect(reason)}")
          state
      end

    schedule_run(state.interval)
    {:noreply, new_state}
  end

  defp schedule_run(interval) do
    Process.send_after(self(), :run, interval)
  end
end
