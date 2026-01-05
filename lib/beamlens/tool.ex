defmodule Beamlens.Tool do
  @moduledoc """
  A tool that can be executed by the agent.

  Each tool bundles its metadata with an execute function,
  making tools first-class data structures that can be
  filtered, composed, and passed around.

  ## Example

      %Beamlens.Tool{
        name: :pool_stats,
        intent: "get_pool_stats",
        description: "Get connection pool statistics",
        execute: fn -> %{size: 10, available: 7} end
      }
  """

  @type t :: %__MODULE__{
          name: atom(),
          intent: String.t(),
          description: String.t(),
          execute: (-> map())
        }

  @enforce_keys [:name, :intent, :description, :execute]
  defstruct [:name, :intent, :description, :execute]
end
