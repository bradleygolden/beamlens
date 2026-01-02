defmodule Beamlens.Baml do
  @moduledoc """
  BAML client for BeamLens.

  This module generates type-safe Elixir modules from BAML definitions.
  Available generated modules:

    * `Beamlens.Baml.BeamMetrics` - Input metrics struct
    * `Beamlens.Baml.MemoryStats` - Memory statistics struct
    * `Beamlens.Baml.HealthReport` - Output health report struct
    * `Beamlens.Baml.AnalyzeBeamHealth` - Function module with `call/2`
  """

  use BamlElixir.Client, path: {:beamlens, "priv/baml_src"}
end
