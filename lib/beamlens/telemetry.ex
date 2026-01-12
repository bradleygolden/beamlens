defmodule Beamlens.Telemetry do
  @moduledoc """
  Telemetry events emitted by BeamLens.

  All events include a `trace_id` for correlating events within a single operator run.
  Events follow the standard `:start`, `:stop`, `:exception` lifecycle pattern
  used by Phoenix, Oban, and other Elixir libraries.

  ## Event Schema

  **Start events** include `%{system_time: integer}` measurement.

  **Stop events** include `%{duration: integer}` measurement (native time units).

  **Exception events** include `%{duration: integer}` measurement and metadata:
  `%{kind: :error | :throw | :exit, reason: term(), stacktrace: list()}`.

  ## LLM Events

  * `[:beamlens, :llm, :start]` - LLM call starting
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{trace_id: String.t(), iteration: integer, context_size: integer}`

  * `[:beamlens, :llm, :stop]` - LLM call completed
    - Measurements: `%{duration: integer}`
    - Metadata: `%{trace_id: String.t(), iteration: integer,
                   tool_selected: String.t(), intent: String.t(), response: struct()}`

  * `[:beamlens, :llm, :exception]` - LLM call failed
    - Measurements: `%{duration: integer}`
    - Metadata: `%{trace_id: String.t(), iteration: integer,
                   kind: atom(), reason: term(), stacktrace: list()}`

  ## Tool Events

  * `[:beamlens, :tool, :start]` - Tool execution starting
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{trace_id: String.t(), iteration: integer,
                   tool_name: String.t(), intent: String.t()}`

  * `[:beamlens, :tool, :stop]` - Tool execution completed
    - Measurements: `%{duration: integer}`
    - Metadata: `%{trace_id: String.t(), iteration: integer,
                   tool_name: String.t(), intent: String.t(), result: map()}`

  * `[:beamlens, :tool, :exception]` - Tool execution failed
    - Measurements: `%{duration: integer}`
    - Metadata: `%{trace_id: String.t(), iteration: integer, tool_name: String.t(),
                   kind: atom(), reason: term(), stacktrace: list()}`

  ## Operator Events

  * `[:beamlens, :operator, :started]` - Operator server started
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{operator: atom()}`

  * `[:beamlens, :operator, :iteration_start]` - Operator iteration starting
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{operator: atom(), trace_id: String.t(), iteration: integer, operator_state: atom()}`

  * `[:beamlens, :operator, :state_change]` - Operator state changed
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{operator: atom(), trace_id: String.t(), from: atom(), to: atom(), reason: String.t()}`

  * `[:beamlens, :operator, :notification_sent]` - Operator sent a notification
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{operator: atom(), trace_id: String.t(), notification: Notification.t()}`

  * `[:beamlens, :operator, :get_notifications]` - Operator retrieved notifications
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{operator: atom(), trace_id: String.t(), count: integer}`

  * `[:beamlens, :operator, :take_snapshot]` - Operator captured a snapshot
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{operator: atom(), trace_id: String.t(), snapshot_id: String.t()}`

  * `[:beamlens, :operator, :get_snapshot]` - Operator retrieved a snapshot
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{operator: atom(), trace_id: String.t(), snapshot_id: String.t()}`

  * `[:beamlens, :operator, :get_snapshots]` - Operator retrieved multiple snapshots
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{operator: atom(), trace_id: String.t(), count: integer}`

  * `[:beamlens, :operator, :execute_start]` - Operator Lua execution starting
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{operator: atom(), trace_id: String.t(), code: String.t()}`

  * `[:beamlens, :operator, :execute_complete]` - Operator Lua execution completed
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{operator: atom(), trace_id: String.t(), code: String.t(), result: term()}`

  * `[:beamlens, :operator, :execute_error]` - Operator Lua execution failed
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{operator: atom(), trace_id: String.t(), code: String.t(), reason: term()}`

  * `[:beamlens, :operator, :wait]` - Operator sleeping
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{operator: atom(), trace_id: String.t(), ms: integer}`

  * `[:beamlens, :operator, :think]` - Operator recorded a thought
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{operator: atom(), trace_id: String.t(), thought: String.t()}`

  * `[:beamlens, :operator, :llm_error]` - Operator LLM call failed
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{operator: atom(), trace_id: String.t(), reason: term(),
                   retry_count: integer, will_retry: boolean}`

  * `[:beamlens, :operator, :loop_stopped]` - Operator loop stopped normally
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{operator: atom(), final_state: atom()}`

  * `[:beamlens, :operator, :notification_failed]` - Notification creation failed
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{operator: atom(), trace_id: String.t(), reason: String.t()}`

  * `[:beamlens, :operator, :unexpected_message]` - GenServer received unexpected message
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{operator: atom(), message: String.t()}`

  ## Coordinator Events

  * `[:beamlens, :coordinator, :started]` - Coordinator server started
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{running: boolean, notification_count: integer}`

  * `[:beamlens, :coordinator, :notification_received]` - Notification queued for correlation
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{notification_id: String.t(), operator: atom()}`

  * `[:beamlens, :coordinator, :iteration_start]` - Coordinator analysis iteration starting
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{trace_id: String.t(), iteration: integer}`

  * `[:beamlens, :coordinator, :get_notifications]` - Coordinator retrieved notifications
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{trace_id: String.t(), status: atom(), count: integer}`

  * `[:beamlens, :coordinator, :update_notification_statuses]` - Coordinator updated notification statuses
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{trace_id: String.t(), notification_ids: list(String.t()), status: atom()}`

  * `[:beamlens, :coordinator, :insight_produced]` - Coordinator created an insight
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{trace_id: String.t(), insight: Insight.t()}`

  * `[:beamlens, :coordinator, :done]` - Coordinator analysis loop completed
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{trace_id: String.t(), has_unread: boolean}`

  * `[:beamlens, :coordinator, :loop_stopped]` - Coordinator loop stopped
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{reason: atom()}`

  * `[:beamlens, :coordinator, :llm_error]` - Coordinator LLM call failed
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{trace_id: String.t(), reason: term()}`

  * `[:beamlens, :coordinator, :unexpected_message]` - GenServer received unexpected message
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{running: boolean, notification_count: integer, message: String.t()}`

  * `[:beamlens, :coordinator, :remote_notification_received]` - Notification received from another node via PubSub
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{notification_id: String.t(), operator: atom(), source_node: node()}`

  * `[:beamlens, :coordinator, :takeover]` - Coordinator shutdown for Highlander takeover
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{notification_count: integer}`

  ## Compaction Events

  * `[:beamlens, :compaction, :start]` - Context compaction starting
    - Measurements: `%{system_time: integer, message_count: integer}`
    - Metadata: `%{trace_id: String.t(), iteration: integer, strategy: module(), config: map()}`

  * `[:beamlens, :compaction, :stop]` - Context compaction completed
    - Measurements: `%{system_time: integer, message_count: integer}`
    - Metadata: `%{trace_id: String.t(), iteration: integer}`

  ## Example Handler

      :telemetry.attach(
        "beamlens-notifications",
        [:beamlens, :operator, :notification_sent],
        fn _event, _measurements, metadata, _config ->
          Logger.warning("BeamLens notification: \#{metadata.notification.summary}")
        end,
        nil
      )

  ## Attaching to All Events

      :telemetry.attach_many(
        "my-handler",
        Beamlens.Telemetry.event_names(),
        &MyHandler.handle_event/4,
        nil
      )
  """

  @doc """
  Returns all telemetry event names that can be emitted.
  """
  def event_names do
    [
      [:beamlens, :llm, :start],
      [:beamlens, :llm, :stop],
      [:beamlens, :llm, :exception],
      [:beamlens, :tool, :start],
      [:beamlens, :tool, :stop],
      [:beamlens, :tool, :exception],
      [:beamlens, :operator, :started],
      [:beamlens, :operator, :iteration_start],
      [:beamlens, :operator, :state_change],
      [:beamlens, :operator, :notification_sent],
      [:beamlens, :operator, :notification_failed],
      [:beamlens, :operator, :get_notifications],
      [:beamlens, :operator, :take_snapshot],
      [:beamlens, :operator, :get_snapshot],
      [:beamlens, :operator, :get_snapshots],
      [:beamlens, :operator, :execute_start],
      [:beamlens, :operator, :execute_complete],
      [:beamlens, :operator, :execute_error],
      [:beamlens, :operator, :wait],
      [:beamlens, :operator, :think],
      [:beamlens, :operator, :llm_error],
      [:beamlens, :operator, :loop_stopped],
      [:beamlens, :operator, :unexpected_message],
      [:beamlens, :coordinator, :started],
      [:beamlens, :coordinator, :notification_received],
      [:beamlens, :coordinator, :iteration_start],
      [:beamlens, :coordinator, :get_notifications],
      [:beamlens, :coordinator, :update_notification_statuses],
      [:beamlens, :coordinator, :insight_produced],
      [:beamlens, :coordinator, :done],
      [:beamlens, :coordinator, :loop_stopped],
      [:beamlens, :coordinator, :llm_error],
      [:beamlens, :coordinator, :unexpected_message],
      [:beamlens, :coordinator, :remote_notification_received],
      [:beamlens, :coordinator, :takeover],
      [:beamlens, :compaction, :start],
      [:beamlens, :compaction, :stop]
    ]
  end

  @doc """
  Generates a unique trace ID for an operator run.
  """
  def generate_trace_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  @doc """
  Executes a tool with telemetry span events.

  Emits `:start`, `:stop`, and `:exception` events for the tool execution.
  """
  def tool_span(metadata, fun) do
    start_time = System.monotonic_time()

    :telemetry.execute(
      [:beamlens, :tool, :start],
      %{system_time: System.system_time()},
      metadata
    )

    try do
      result = fun.()

      :telemetry.execute(
        [:beamlens, :tool, :stop],
        %{duration: System.monotonic_time() - start_time},
        Map.put(metadata, :result, result)
      )

      result
    rescue
      exception ->
        stacktrace = __STACKTRACE__

        :telemetry.execute(
          [:beamlens, :tool, :exception],
          %{duration: System.monotonic_time() - start_time},
          Map.merge(metadata, %{kind: :error, reason: exception, stacktrace: stacktrace})
        )

        reraise exception, stacktrace
    end
  end

  @doc """
  Emits a tool start event.
  """
  def emit_tool_start(metadata) do
    :telemetry.execute(
      [:beamlens, :tool, :start],
      %{system_time: System.system_time()},
      metadata
    )
  end

  @doc """
  Emits a tool stop event with the tool result and duration.

  `start_time` should be captured via `System.monotonic_time()` before tool execution.
  """
  def emit_tool_stop(metadata, result, start_time) do
    :telemetry.execute(
      [:beamlens, :tool, :stop],
      %{duration: System.monotonic_time() - start_time},
      Map.put(metadata, :result, result)
    )
  end

  @doc """
  Emits a tool exception event with duration and exception details.

  `start_time` should be captured via `System.monotonic_time()` before tool execution.
  `kind` is the exception type (`:error`, `:throw`, or `:exit`).
  `stacktrace` is the exception stacktrace.
  """
  def emit_tool_exception(metadata, error, start_time, kind \\ :error, stacktrace \\ []) do
    :telemetry.execute(
      [:beamlens, :tool, :exception],
      %{duration: System.monotonic_time() - start_time},
      Map.merge(metadata, %{kind: kind, reason: error, stacktrace: stacktrace})
    )
  end

  @doc """
  Attaches a default logging handler to all BeamLens telemetry events.

  ## Options

  - `:level` - Log level to use (default: `:debug`)
  """
  def attach_default_logger(opts \\ []) do
    level = Keyword.get(opts, :level, :debug)

    :telemetry.attach_many(
      "beamlens-telemetry-default-logger",
      event_names(),
      &__MODULE__.log_event/4,
      %{level: level}
    )
  end

  @doc """
  Detaches the default logging handler.
  """
  def detach_default_logger do
    :telemetry.detach("beamlens-telemetry-default-logger")
  end

  @doc false
  def log_event(event, measurements, metadata, config) do
    require Logger

    level = Map.get(config, :level, :debug)
    event_name = Enum.join(event, ".")
    trace_id = Map.get(metadata, :trace_id, "unknown")

    Logger.log(level, fn ->
      "[#{event_name}] trace_id=#{trace_id} #{format_measurements(measurements)}"
    end)
  end

  defp format_measurements(measurements) do
    Enum.map_join(measurements, " ", fn {k, v} -> "#{k}=#{v}" end)
  end
end
