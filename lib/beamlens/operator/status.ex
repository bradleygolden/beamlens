defmodule Beamlens.Operator.Status do
  @moduledoc """
  Status information for a running Operator.

  Returned by `Beamlens.Operator.status/1`.
  """

  defstruct [:operator, :state, :iteration, :running]

  @type t :: %__MODULE__{
          operator: module(),
          state: :healthy | :observing | :warning | :critical,
          iteration: non_neg_integer(),
          running: boolean()
        }
end
