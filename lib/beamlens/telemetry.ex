defmodule Beamlens.Telemetry do
  @moduledoc """
  Telemetry events emitted by BeamLens.

  ## Events

  * `[:beamlens, :agent, :start]` - Agent run starting
  * `[:beamlens, :agent, :stop]` - Agent run completed
  * `[:beamlens, :agent, :exception]` - Agent run failed

  ## Measurements

  The `:stop` event includes:

  * `duration` - Time taken in native units (nanoseconds)

  ## Metadata

  The `:stop` event includes:

  * `node` - Node name as string
  * `status` - `:healthy`, `:warning`, or `:critical`
  * `report` - Full `HealthReport` struct

  ## Example Handler

      :telemetry.attach(
        "beamlens-alerts",
        [:beamlens, :agent, :stop],
        fn _event, _measurements, %{status: :critical} = metadata, _config ->
          Logger.error("BeamLens critical: \#{metadata.report.summary}")
        end,
        nil
      )
  """

  @doc false
  def span(metadata, fun) do
    :telemetry.span([:beamlens, :agent], metadata, fun)
  end
end
