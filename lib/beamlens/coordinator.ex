defmodule Beamlens.Coordinator do
  @moduledoc """
  GenServer that correlates notifications from operators into insights.

  Subscribes to `[:beamlens, :operator, :notification_sent]` telemetry events and
  manages a notification inbox with status tracking. Runs an LLM tool-calling loop
  to identify patterns across notifications and emit insights.

  ## Notification States

  - `:unread` - New notification, not yet processed
  - `:acknowledged` - Currently being analyzed
  - `:resolved` - Processed (correlated into insight or dismissed)

  ## Single Node Example

      {:ok, pid} = Beamlens.Coordinator.start_link(
        client_registry: %{...}
      )

  ## Clustered Example

  When running in a cluster with PubSub, the Coordinator can receive notifications
  from other nodes:

      {:ok, pid} = Beamlens.Coordinator.start_link(
        client_registry: %{...},
        pubsub: MyApp.PubSub
      )

  In clustered mode, wrap with Highlander to ensure only one runs cluster-wide:

      children = [
        {Highlander, {Beamlens.Coordinator, client_registry: %{...}, pubsub: MyApp.PubSub}}
      ]

  """

  use GenServer

  alias Beamlens.Coordinator.{Insight, Tools}

  alias Beamlens.Coordinator.Tools.{
    Done,
    GetNotifications,
    ProduceInsight,
    Think,
    UpdateNotificationStatuses
  }

  alias Beamlens.LLM.Utils
  alias Beamlens.NotificationForwarder
  alias Beamlens.Operator.Notification
  alias Beamlens.Telemetry
  alias Puck.Context

  @telemetry_handler_id "beamlens-coordinator-notifications"

  defstruct [
    :client,
    :client_registry,
    :context,
    :pending_task,
    :pending_trace_id,
    :pubsub,
    notifications: %{},
    iteration: 0,
    running: false
  ]

  @doc """
  Starts the coordinator process.

  ## Options

    * `:name` - Optional process name for registration (default: `__MODULE__`)
    * `:client_registry` - Optional LLM provider configuration map
    * `:pubsub` - Phoenix.PubSub module for cross-node notifications (optional)
    * `:compaction_max_tokens` - Token threshold for compaction (default: 50_000)
    * `:compaction_keep_last` - Messages to keep verbatim after compaction (default: 5)

  """
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Returns the current coordinator status.
  """
  def status(server \\ __MODULE__) do
    GenServer.call(server, :status)
  end

  @impl true
  def init(opts) do
    client = build_puck_client(Keyword.get(opts, :client_registry), opts)
    pubsub = Keyword.get(opts, :pubsub)

    :telemetry.attach(
      @telemetry_handler_id,
      [:beamlens, :operator, :notification_sent],
      &__MODULE__.handle_telemetry_event/4,
      %{coordinator: self()}
    )

    if pubsub do
      Phoenix.PubSub.subscribe(pubsub, NotificationForwarder.pubsub_topic())
    end

    state = %__MODULE__{
      client: client,
      client_registry: Keyword.get(opts, :client_registry),
      pubsub: pubsub,
      context: Context.new()
    }

    emit_telemetry(:started, state)

    {:ok, state}
  end

  @impl true
  def terminate(reason, %{pending_task: %Task{} = task} = state) do
    Task.shutdown(task, :brutal_kill)
    :telemetry.detach(@telemetry_handler_id)
    maybe_emit_takeover(reason, state)
  end

  def terminate(reason, state) do
    :telemetry.detach(@telemetry_handler_id)
    maybe_emit_takeover(reason, state)
  end

  defp maybe_emit_takeover(:shutdown, state) do
    :telemetry.execute(
      [:beamlens, :coordinator, :takeover],
      %{system_time: System.system_time()},
      %{notification_count: map_size(state.notifications)}
    )
  end

  defp maybe_emit_takeover(_reason, _state), do: :ok

  @impl true
  def handle_cast({:notification_received, %Notification{} = notification}, state) do
    new_notifications =
      Map.put(state.notifications, notification.id, %{notification: notification, status: :unread})

    new_state = %{state | notifications: new_notifications}

    emit_telemetry(:notification_received, new_state, %{
      notification_id: notification.id,
      operator: notification.operator
    })

    if state.running do
      {:noreply, new_state}
    else
      {:noreply, %{new_state | running: true, iteration: 0, context: Context.new()},
       {:continue, :loop}}
    end
  end

  @impl true
  def handle_continue(:loop, state) do
    trace_id = Telemetry.generate_trace_id()

    emit_telemetry(:iteration_start, state, %{
      trace_id: trace_id,
      iteration: state.iteration
    })

    context = %{
      state.context
      | metadata: Map.put(state.context.metadata || %{}, :trace_id, trace_id)
    }

    task =
      Task.async(fn ->
        Puck.call(state.client, "Process notifications", context, output_schema: Tools.schema())
      end)

    {:noreply, %{state | pending_task: task, pending_trace_id: trace_id}}
  end

  @impl true
  def handle_info({ref, result}, %{pending_task: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    state = %{state | pending_task: nil}

    case result do
      {:ok, response, new_context} ->
        parsed = ensure_parsed(response.content)
        handle_action(parsed, %{state | context: new_context}, state.pending_trace_id)

      {:error, reason} ->
        emit_telemetry(:llm_error, state, %{trace_id: state.pending_trace_id, reason: reason})
        {:noreply, %{state | running: false, pending_trace_id: nil}}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{pending_task: %Task{ref: ref}} = state) do
    emit_telemetry(:llm_error, state, %{
      trace_id: state.pending_trace_id,
      reason: {:task_crashed, reason}
    })

    {:noreply, %{state | pending_task: nil, pending_trace_id: nil, running: false}}
  end

  def handle_info({:beamlens_notification, %Notification{} = notification, source_node}, state) do
    if source_node == node() do
      {:noreply, state}
    else
      emit_telemetry(:remote_notification_received, state, %{
        notification_id: notification.id,
        operator: notification.operator,
        source_node: source_node
      })

      new_notifications =
        Map.put(state.notifications, notification.id, %{
          notification: notification,
          status: :unread
        })

      new_state = %{state | notifications: new_notifications}

      if state.running do
        {:noreply, new_state}
      else
        {:noreply, %{new_state | running: true, iteration: 0, context: Context.new()},
         {:continue, :loop}}
      end
    end
  end

  def handle_info(msg, state) do
    emit_telemetry(:unexpected_message, state, %{message: inspect(msg)})
    {:noreply, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      running: state.running,
      notification_count: map_size(state.notifications),
      unread_count: count_by_status(state.notifications, :unread),
      iteration: state.iteration
    }

    {:reply, status, state}
  end

  @doc false
  def handle_telemetry_event(_event, _measurements, %{notification: notification}, %{
        coordinator: pid
      }) do
    GenServer.cast(pid, {:notification_received, notification})
  end

  defp handle_action(%GetNotifications{status: status}, state, trace_id) do
    notifications = filter_notifications(state.notifications, status)

    result =
      Enum.map(notifications, fn {id, %{notification: notification, status: s}} ->
        %{
          id: id,
          status: s,
          operator: notification.operator,
          anomaly_type: notification.anomaly_type,
          severity: notification.severity,
          summary: notification.summary,
          detected_at: notification.detected_at
        }
      end)

    emit_telemetry(:get_notifications, state, %{trace_id: trace_id, count: length(result)})

    new_context = Utils.add_result(state.context, result)

    new_state = %{
      state
      | context: new_context,
        iteration: state.iteration + 1,
        pending_trace_id: nil
    }

    {:noreply, new_state, {:continue, :loop}}
  end

  defp handle_action(
         %UpdateNotificationStatuses{notification_ids: ids, status: status, reason: reason},
         state,
         trace_id
       ) do
    new_notifications = update_notifications_status(state.notifications, ids, status)

    result = %{updated: ids, status: status}
    result = if reason, do: Map.put(result, :reason, reason), else: result

    emit_telemetry(:update_notification_statuses, state, %{
      trace_id: trace_id,
      notification_ids: ids,
      status: status
    })

    new_context = Utils.add_result(state.context, result)

    new_state = %{
      state
      | notifications: new_notifications,
        context: new_context,
        iteration: state.iteration + 1,
        pending_trace_id: nil
    }

    {:noreply, new_state, {:continue, :loop}}
  end

  defp handle_action(%ProduceInsight{} = tool, state, trace_id) do
    insight =
      Insight.new(%{
        notification_ids: tool.notification_ids,
        correlation_type: tool.correlation_type,
        summary: tool.summary,
        root_cause_hypothesis: tool.root_cause_hypothesis,
        confidence: tool.confidence
      })

    emit_telemetry(:insight_produced, state, %{
      trace_id: trace_id,
      insight: insight
    })

    new_notifications =
      update_notifications_status(state.notifications, tool.notification_ids, :resolved)

    new_context = Utils.add_result(state.context, %{insight_produced: insight.id})

    new_state = %{
      state
      | notifications: new_notifications,
        context: new_context,
        iteration: state.iteration + 1,
        pending_trace_id: nil
    }

    {:noreply, new_state, {:continue, :loop}}
  end

  defp handle_action(%Done{}, state, trace_id) do
    has_unread = Enum.any?(state.notifications, fn {_, %{status: s}} -> s == :unread end)

    emit_telemetry(:done, state, %{trace_id: trace_id, has_unread: has_unread})

    if has_unread do
      fresh_context = Context.new()

      {:noreply, %{state | context: fresh_context, iteration: 0, pending_trace_id: nil},
       {:continue, :loop}}
    else
      {:noreply, %{state | running: false, pending_trace_id: nil}}
    end
  end

  defp handle_action(%Think{thought: thought}, state, trace_id) do
    emit_telemetry(:think, state, %{trace_id: trace_id})

    result = %{thought: thought, recorded: true}
    new_context = Utils.add_result(state.context, result)

    new_state = %{
      state
      | context: new_context,
        iteration: state.iteration + 1,
        pending_trace_id: nil
    }

    {:noreply, new_state, {:continue, :loop}}
  end

  defp filter_notifications(notifications, nil), do: notifications

  defp filter_notifications(notifications, status) do
    notifications
    |> Enum.filter(fn {_, %{status: s}} -> s == status end)
    |> Map.new()
  end

  defp update_notifications_status(notifications, ids, new_status) do
    Enum.reduce(ids, notifications, fn id, acc ->
      case Map.get(acc, id) do
        nil -> acc
        entry -> Map.put(acc, id, %{entry | status: new_status})
      end
    end)
  end

  defp count_by_status(notifications, status) do
    Enum.count(notifications, fn {_, %{status: s}} -> s == status end)
  end

  defp ensure_parsed(%{__struct__: _} = struct), do: struct

  defp ensure_parsed(map) when is_map(map) do
    {:ok, parsed} = Zoi.parse(Tools.schema(), map)
    parsed
  end

  defp build_puck_client(client_registry, opts) do
    operator_descriptions = build_operator_descriptions()

    backend_config =
      %{
        function: "CoordinatorLoop",
        args_format: :auto,
        args: fn messages ->
          %{
            messages: Utils.format_messages_for_baml(messages),
            operator_descriptions: operator_descriptions
          }
        end,
        path: Application.app_dir(:beamlens, "priv/baml_src")
      }
      |> Utils.maybe_add_client_registry(client_registry)

    Puck.Client.new(
      {Puck.Backends.Baml, backend_config},
      hooks: Beamlens.Telemetry.Hooks,
      auto_compaction: build_compaction_config(opts)
    )
  end

  defp build_operator_descriptions do
    operators = Application.get_env(:beamlens, :operators, [])

    operators
    |> Enum.map(&Beamlens.Operator.Supervisor.resolve_skill/1)
    |> Enum.filter(&match?({:ok, _}, &1))
    |> Enum.map_join("\n", fn {:ok, {name, skill}} -> "- #{name}: #{skill.description()}" end)
  end

  defp build_compaction_config(opts) do
    max_tokens = Keyword.get(opts, :compaction_max_tokens, 50_000)
    keep_last = Keyword.get(opts, :compaction_keep_last, 5)

    {:summarize,
     max_tokens: max_tokens, keep_last: keep_last, prompt: coordinator_compaction_prompt()}
  end

  defp coordinator_compaction_prompt do
    """
    Summarize this notification analysis session, preserving:
    - Notification IDs and their statuses (exact IDs required)
    - Correlations identified between notifications
    - Insights produced and their reasoning
    - Pending analysis or patterns being investigated
    - Any notifications still needing attention

    Be concise. This summary will be used to continue correlation analysis.
    """
  end

  defp emit_telemetry(event, state, extra \\ %{}) do
    :telemetry.execute(
      [:beamlens, :coordinator, event],
      %{system_time: System.system_time()},
      Map.merge(
        %{
          running: state.running,
          notification_count: map_size(state.notifications)
        },
        extra
      )
    )
  end
end
