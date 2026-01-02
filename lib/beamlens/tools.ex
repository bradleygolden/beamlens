defmodule Beamlens.Tools do
  @moduledoc """
  Tool response structs and union schema for the agent loop.

  Each struct represents a possible tool selection from the LLM.
  The union schema parses raw BAML responses into typed structs.
  """

  defmodule GetSystemInfo do
    @moduledoc false
    defstruct [:intent]
  end

  defmodule GetMemoryStats do
    @moduledoc false
    defstruct [:intent]
  end

  defmodule GetProcessStats do
    @moduledoc false
    defstruct [:intent]
  end

  defmodule GetSchedulerStats do
    @moduledoc false
    defstruct [:intent]
  end

  defmodule GetAtomStats do
    @moduledoc false
    defstruct [:intent]
  end

  defmodule GetPersistentTerms do
    @moduledoc false
    defstruct [:intent]
  end

  defmodule Done do
    @moduledoc false
    defstruct [:intent, :report]
  end

  @doc """
  Returns a ZOI union schema for parsing SelectTool responses into structs.

  Uses discriminated union pattern matching on the `intent` field.
  """
  def schema do
    Zoi.union([
      tool_schema(GetSystemInfo, "get_system_info"),
      tool_schema(GetMemoryStats, "get_memory_stats"),
      tool_schema(GetProcessStats, "get_process_stats"),
      tool_schema(GetSchedulerStats, "get_scheduler_stats"),
      tool_schema(GetAtomStats, "get_atom_stats"),
      tool_schema(GetPersistentTerms, "get_persistent_terms"),
      done_schema()
    ])
  end

  defp tool_schema(module, intent_value) do
    Zoi.object(%{intent: Zoi.literal(intent_value)})
    |> Zoi.transform(fn data -> {:ok, struct!(module, data)} end)
  end

  defp done_schema do
    Zoi.object(%{
      intent: Zoi.literal("done"),
      report: Beamlens.HealthReport.schema()
    })
    |> Zoi.transform(fn data -> {:ok, struct!(Done, data)} end)
  end
end
