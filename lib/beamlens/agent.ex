defmodule Beamlens.Agent do
  @moduledoc """
  BAML-based agent that analyzes BEAM health using a tool-calling loop.

  Uses Claude Haiku via BAML to iteratively gather VM metrics and produce
  structured health assessments. The agent selects which tools to call
  and accumulates context until it generates a final report.

  ## Architecture

  The agent loop:
  1. Calls `SelectTool` BAML function with conversation history
  2. Pattern matches on the `intent` field to determine which tool was selected
  3. Executes the tool and adds result to context
  4. Repeats until agent calls `done` with a HealthReport

  Uses `Strider.Context` for immutable conversation history management.
  """

  require Logger

  alias Strider.Context
  alias Beamlens.Baml.SelectTool
  alias Beamlens.Baml.Message

  @default_max_iterations 10

  @doc """
  Run a health analysis using the agent loop.

  The agent will iteratively select tools to gather information,
  then generate a final health report.

  ## Options

    * `:max_iterations` - Maximum tool calls before forcing completion (default: 10)

  ## Examples

      {:ok, report} = Beamlens.Agent.run()
      report.status
      #=> "healthy"
  """
  def run(opts \\ []) do
    max_iterations = Keyword.get(opts, :max_iterations, @default_max_iterations)

    context =
      Context.new(
        metadata: %{
          started_at: DateTime.utc_now(),
          node: Node.self()
        }
      )

    loop(context, max_iterations)
  end

  # Loop terminates when max iterations reached
  defp loop(_context, 0) do
    Logger.warning("[BeamLens] Agent reached max iterations without completing")
    {:error, :max_iterations_exceeded}
  end

  defp loop(context, remaining) do
    messages = context |> Context.messages() |> format_for_baml()

    case SelectTool.call(%{messages: messages}, %{}) do
      {:ok, tool_response} ->
        Logger.debug("[BeamLens] Agent selected: #{inspect(tool_response.intent)}")
        execute_tool(tool_response, context, remaining - 1)

      {:error, reason} = error ->
        Logger.warning("[BeamLens] SelectTool failed: #{inspect(reason)}")
        error
    end
  end

  # Dispatch on the `intent` field (pattern from BAML docs)

  defp execute_tool(%{intent: "done", report: report}, _context, _remaining) do
    Logger.info("[BeamLens] Agent completed with status: #{report.status}")
    {:ok, report}
  end

  defp execute_tool(%{intent: "get_system_info"}, context, remaining) do
    result = Beamlens.Collector.system_info()
    continue(context, "get_system_info", result, remaining)
  end

  defp execute_tool(%{intent: "get_memory_stats"}, context, remaining) do
    result = Beamlens.Collector.memory_stats()
    continue(context, "get_memory_stats", result, remaining)
  end

  defp execute_tool(%{intent: "get_process_stats"}, context, remaining) do
    result = Beamlens.Collector.process_stats()
    continue(context, "get_process_stats", result, remaining)
  end

  defp execute_tool(%{intent: "get_scheduler_stats"}, context, remaining) do
    result = Beamlens.Collector.scheduler_stats()
    continue(context, "get_scheduler_stats", result, remaining)
  end

  defp execute_tool(%{intent: "get_atom_stats"}, context, remaining) do
    result = Beamlens.Collector.atom_stats()
    continue(context, "get_atom_stats", result, remaining)
  end

  defp execute_tool(%{intent: "get_persistent_terms"}, context, remaining) do
    result = Beamlens.Collector.persistent_terms()
    continue(context, "get_persistent_terms", result, remaining)
  end

  defp execute_tool(unknown, _context, _remaining) do
    Logger.warning("[BeamLens] Unknown tool response: #{inspect(unknown)}")
    {:error, {:unknown_tool, unknown}}
  end

  defp continue(context, tool_name, result, remaining) do
    Logger.debug("[BeamLens] Tool #{tool_name} returned: #{inspect(result)}")

    context
    |> Context.add_message(:tool, Jason.encode!(result), %{tool: tool_name})
    |> loop(remaining)
  end

  # Convert Strider.Context messages to BAML Message format
  defp format_for_baml(messages) do
    Enum.map(messages, fn msg ->
      %Message{
        role: to_string(msg.role),
        content: msg.content
      }
    end)
  end
end
