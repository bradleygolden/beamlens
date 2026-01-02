defmodule Beamlens.Baml do
  @moduledoc """
  BAML client for BeamLens.

  This module generates type-safe Elixir modules from BAML definitions.
  """

  use BamlElixir.Client, path: {:beamlens, "priv/baml_src"}
end
