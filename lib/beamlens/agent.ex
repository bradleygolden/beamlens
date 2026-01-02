defmodule Beamlens.Agent do
  @moduledoc """
  Strider-based agent that analyzes BEAM health using a tool-calling loop.

  Uses Claude Haiku via BAML to iteratively gather VM metrics and produce
  structured health assessments. The agent selects which tools to call
  and accumulates context until it generates a final analysis.

  ## Architecture

  The agent loop:
  1. Calls `SelectTool` BAML function with conversation history
  2. Pattern matches on tool struct type to determine which tool was selected
  3. Executes the tool and adds result to context
  4. Repeats until agent selects `Done` with a HealthAnalysis

  Uses `Strider.Agent` for LLM configuration and `Strider.Context` for
  immutable conversation history management.
  """

  require Logger

  alias Strider.Context
  alias Beamlens.Tools

  @default_max_iterations 10

  @doc """
  Run a health analysis using the agent loop.

  The agent will iteratively select tools to gather information,
  then generate a final health analysis.

  ## Options

    * `:max_iterations` - Maximum tool calls before forcing completion (default: 10)
    * `:llm_client` - BAML client name to use (default: "Haiku", or "Ollama" for local)

  ## Examples

      {:ok, analysis} = Beamlens.Agent.run()
      analysis.status
      #=> :healthy

      # Use local Ollama model
      {:ok, analysis} = Beamlens.Agent.run(llm_client: "Ollama")
  """
  def run(opts \\ []) do
    max_iterations = Keyword.get(opts, :max_iterations, @default_max_iterations)
    llm_client = Keyword.get(opts, :llm_client)

    backend_config =
      [
        function: "SelectTool",
        path: "priv/baml_src",
        prefix: Beamlens.Baml,
        args_format: :messages
      ]
      |> maybe_add_llm_client(llm_client)

    agent = Strider.Agent.new({Strider.Backends.Baml, backend_config})

    context =
      Context.new(
        metadata: %{
          started_at: DateTime.utc_now(),
          node: Node.self()
        }
      )

    loop(agent, context, max_iterations)
  end

  defp loop(_agent, _context, 0) do
    Logger.warning("[BeamLens] Agent reached max iterations without completing")
    {:error, :max_iterations_exceeded}
  end

  defp loop(agent, context, remaining) do
    case Strider.call(agent, [], context, output_schema: Tools.schema()) do
      {:ok, response, new_context} ->
        Logger.debug("[BeamLens] Agent selected: #{inspect(response.content)}")
        execute_tool(response.content, agent, new_context, remaining - 1)

      {:error, reason} = error ->
        Logger.warning("[BeamLens] SelectTool failed: #{inspect(reason)}")
        error
    end
  end

  defp execute_tool(%Tools.Done{analysis: analysis}, _agent, _context, _remaining) do
    Logger.info("[BeamLens] Agent completed with status: #{analysis.status}")
    {:ok, analysis}
  end

  defp execute_tool(%Tools.GetSystemInfo{}, agent, context, remaining) do
    continue(agent, context, "get_system_info", Beamlens.Collector.system_info(), remaining)
  end

  defp execute_tool(%Tools.GetMemoryStats{}, agent, context, remaining) do
    continue(agent, context, "get_memory_stats", Beamlens.Collector.memory_stats(), remaining)
  end

  defp execute_tool(%Tools.GetProcessStats{}, agent, context, remaining) do
    continue(agent, context, "get_process_stats", Beamlens.Collector.process_stats(), remaining)
  end

  defp execute_tool(%Tools.GetSchedulerStats{}, agent, context, remaining) do
    continue(
      agent,
      context,
      "get_scheduler_stats",
      Beamlens.Collector.scheduler_stats(),
      remaining
    )
  end

  defp execute_tool(%Tools.GetAtomStats{}, agent, context, remaining) do
    continue(agent, context, "get_atom_stats", Beamlens.Collector.atom_stats(), remaining)
  end

  defp execute_tool(%Tools.GetPersistentTerms{}, agent, context, remaining) do
    continue(
      agent,
      context,
      "get_persistent_terms",
      Beamlens.Collector.persistent_terms(),
      remaining
    )
  end

  defp execute_tool(unknown, _agent, _context, _remaining) do
    Logger.warning("[BeamLens] Unknown tool response: #{inspect(unknown)}")
    {:error, {:unknown_tool, unknown}}
  end

  defp continue(agent, context, tool_name, result, remaining) do
    Logger.debug("[BeamLens] Tool #{tool_name} returned: #{inspect(result)}")

    new_context = add_tool_message(context, Jason.encode!(result), %{tool: tool_name})
    loop(agent, new_context, remaining)
  end

  defp add_tool_message(context, content, metadata) do
    message = %Strider.Message{
      role: :tool,
      content: Strider.Content.wrap(content),
      metadata: metadata
    }

    %{context | messages: context.messages ++ [message]}
  end

  defp maybe_add_llm_client(config, nil), do: config
  defp maybe_add_llm_client(config, client), do: Keyword.put(config, :llm_client, client)
end
