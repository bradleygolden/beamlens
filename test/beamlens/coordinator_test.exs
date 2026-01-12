defmodule Beamlens.CoordinatorTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Beamlens.Coordinator
  alias Beamlens.Coordinator.Insight
  alias Beamlens.Operator.Notification

  defp mock_client do
    Puck.Client.new({Puck.Backends.Mock, error: :test_stop})
  end

  defp start_coordinator(opts \\ []) do
    name = Keyword.get(opts, :name, :"coordinator_#{:erlang.unique_integer([:positive])}")
    opts = Keyword.put(opts, :name, name)
    {:ok, pid} = Coordinator.start_link(opts)

    :sys.replace_state(pid, fn state ->
      %{state | client: mock_client()}
    end)

    {:ok, pid}
  end

  defp stop_coordinator(pid) do
    if Process.alive?(pid) do
      GenServer.stop(pid, :normal)
    end
  end

  defp build_test_notification(overrides \\ %{}) do
    Notification.new(
      Map.merge(
        %{
          operator: :test,
          anomaly_type: "test_anomaly",
          severity: :info,
          summary: "Test notification",
          snapshots: []
        },
        overrides
      )
    )
  end

  defp simulate_notification(pid, notification) do
    GenServer.cast(pid, {:notification_received, notification})
  end

  defp extract_content_text(content) when is_binary(content), do: content

  defp extract_content_text(content) when is_list(content) do
    Enum.map_join(content, "", fn
      %{text: text} -> text
      part when is_struct(part) -> Map.get(part, :text, "")
      _ -> ""
    end)
  end

  defp extract_content_text(_), do: ""

  describe "start_link/1" do
    test "starts with custom name" do
      {:ok, pid} = start_coordinator(name: :test_coordinator)

      assert Process.alive?(pid)

      stop_coordinator(pid)
    end

    test "starts with generated name" do
      {:ok, pid} = start_coordinator()

      assert Process.alive?(pid)

      stop_coordinator(pid)
    end

    test "stores client_registry in state" do
      client_registry = %{primary: "Test", clients: []}

      {:ok, pid} = start_coordinator(client_registry: client_registry)

      state = :sys.get_state(pid)
      assert state.client_registry == client_registry

      stop_coordinator(pid)
    end
  end

  describe "status/1" do
    test "returns current status" do
      {:ok, pid} = start_coordinator()

      status = Coordinator.status(pid)

      assert status.running == false
      assert status.notification_count == 0
      assert status.unread_count == 0
      assert status.iteration == 0

      stop_coordinator(pid)
    end

    test "reflects notification counts accurately" do
      {:ok, pid} = start_coordinator()

      notification1 = build_test_notification(%{anomaly_type: "type1"})
      notification2 = build_test_notification(%{anomaly_type: "type2"})

      :sys.replace_state(pid, fn state ->
        notifications = %{
          notification1.id => %{notification: notification1, status: :unread},
          notification2.id => %{notification: notification2, status: :acknowledged}
        }

        %{state | notifications: notifications}
      end)

      status = Coordinator.status(pid)

      assert status.notification_count == 2
      assert status.unread_count == 1

      stop_coordinator(pid)
    end
  end

  describe "initial state" do
    test "starts with empty notifications" do
      {:ok, pid} = start_coordinator()

      state = :sys.get_state(pid)
      assert state.notifications == %{}

      stop_coordinator(pid)
    end

    test "starts with running false" do
      {:ok, pid} = start_coordinator()

      state = :sys.get_state(pid)
      assert state.running == false

      stop_coordinator(pid)
    end

    test "starts with iteration zero" do
      {:ok, pid} = start_coordinator()

      state = :sys.get_state(pid)
      assert state.iteration == 0

      stop_coordinator(pid)
    end

    test "initializes with fresh context" do
      {:ok, pid} = start_coordinator()

      state = :sys.get_state(pid)
      assert %Puck.Context{} = state.context
      assert state.context.messages == []

      stop_coordinator(pid)
    end
  end

  describe "notification ingestion" do
    test "notification received creates entry with unread status" do
      {:ok, pid} = start_coordinator()

      notification = build_test_notification()

      :sys.replace_state(pid, fn state ->
        %{state | running: true}
      end)

      simulate_notification(pid, notification)

      state = :sys.get_state(pid)

      assert Map.has_key?(state.notifications, notification.id)
      assert state.notifications[notification.id].status == :unread
      assert state.notifications[notification.id].notification == notification

      stop_coordinator(pid)
    end

    test "multiple notifications can coexist" do
      {:ok, pid} = start_coordinator()

      :sys.replace_state(pid, fn state ->
        %{state | running: true}
      end)

      notification1 = build_test_notification(%{anomaly_type: "type1"})
      notification2 = build_test_notification(%{anomaly_type: "type2"})

      simulate_notification(pid, notification1)
      simulate_notification(pid, notification2)

      state = :sys.get_state(pid)

      assert map_size(state.notifications) == 2
      assert Map.has_key?(state.notifications, notification1.id)
      assert Map.has_key?(state.notifications, notification2.id)

      stop_coordinator(pid)
    end

    test "first notification triggers loop start via telemetry" do
      ref = make_ref()
      parent = self()

      :telemetry.attach(
        {ref, :iteration_start},
        [:beamlens, :coordinator, :iteration_start],
        fn _event, _measurements, metadata, _ ->
          send(parent, {:telemetry, :iteration_start, metadata})
        end,
        nil
      )

      {:ok, pid} = start_coordinator()

      notification = build_test_notification()
      simulate_notification(pid, notification)

      assert_receive {:telemetry, :iteration_start, %{iteration: 0}}, 1000

      stop_coordinator(pid)
      :telemetry.detach({ref, :iteration_start})
    end
  end

  describe "handle_action - GetNotifications" do
    test "increments iteration after processing" do
      {:ok, pid} = start_coordinator()

      notification1 = build_test_notification(%{anomaly_type: "type1"})
      notification2 = build_test_notification(%{anomaly_type: "type2"})

      task = Task.async(fn -> :ok end)
      Task.await(task)

      :sys.replace_state(pid, fn state ->
        notifications = %{
          notification1.id => %{notification: notification1, status: :unread},
          notification2.id => %{notification: notification2, status: :acknowledged}
        }

        %{state | notifications: notifications, running: true, pending_task: task}
      end)

      action_map = %{intent: "get_notifications"}
      send(pid, {task.ref, {:ok, %{content: action_map}, Puck.Context.new()}})

      state = :sys.get_state(pid)

      assert state.iteration == 1

      stop_coordinator(pid)
    end

    test "filters by unread status and adds result to context" do
      {:ok, pid} = start_coordinator()

      notification1 = build_test_notification(%{anomaly_type: "type1"})
      notification2 = build_test_notification(%{anomaly_type: "type2"})

      task = Task.async(fn -> :ok end)
      Task.await(task)

      :sys.replace_state(pid, fn state ->
        notifications = %{
          notification1.id => %{notification: notification1, status: :unread},
          notification2.id => %{notification: notification2, status: :acknowledged}
        }

        %{state | notifications: notifications, running: true, pending_task: task}
      end)

      action_map = %{intent: "get_notifications", status: "unread"}
      send(pid, {task.ref, {:ok, %{content: action_map}, Puck.Context.new()}})

      state = :sys.get_state(pid)

      last_message = List.last(state.context.messages)
      content_text = extract_content_text(last_message.content)
      assert content_text =~ notification1.id
      refute content_text =~ notification2.id

      stop_coordinator(pid)
    end
  end

  describe "handle_action - UpdateNotificationStatuses" do
    test "updates single notification status" do
      {:ok, pid} = start_coordinator()

      notification = build_test_notification()
      task = Task.async(fn -> :ok end)
      Task.await(task)

      :sys.replace_state(pid, fn state ->
        notifications = %{notification.id => %{notification: notification, status: :unread}}
        %{state | notifications: notifications, running: true, pending_task: task}
      end)

      action_map = %{
        intent: "update_notification_statuses",
        notification_ids: [notification.id],
        status: "acknowledged"
      }

      send(pid, {task.ref, {:ok, %{content: action_map}, Puck.Context.new()}})

      state = :sys.get_state(pid)

      assert state.notifications[notification.id].status == :acknowledged

      stop_coordinator(pid)
    end

    test "updates multiple notifications" do
      {:ok, pid} = start_coordinator()

      notification1 = build_test_notification(%{anomaly_type: "type1"})
      notification2 = build_test_notification(%{anomaly_type: "type2"})
      task = Task.async(fn -> :ok end)
      Task.await(task)

      :sys.replace_state(pid, fn state ->
        notifications = %{
          notification1.id => %{notification: notification1, status: :unread},
          notification2.id => %{notification: notification2, status: :unread}
        }

        %{state | notifications: notifications, running: true, pending_task: task}
      end)

      action_map = %{
        intent: "update_notification_statuses",
        notification_ids: [notification1.id, notification2.id],
        status: "resolved",
        reason: "Test reason"
      }

      send(pid, {task.ref, {:ok, %{content: action_map}, Puck.Context.new()}})

      state = :sys.get_state(pid)

      assert state.notifications[notification1.id].status == :resolved
      assert state.notifications[notification2.id].status == :resolved

      stop_coordinator(pid)
    end

    test "ignores non-existent notification IDs" do
      {:ok, pid} = start_coordinator()

      notification = build_test_notification()
      task = Task.async(fn -> :ok end)
      Task.await(task)

      :sys.replace_state(pid, fn state ->
        notifications = %{notification.id => %{notification: notification, status: :unread}}
        %{state | notifications: notifications, running: true, pending_task: task}
      end)

      action_map = %{
        intent: "update_notification_statuses",
        notification_ids: [notification.id, "nonexistent_id"],
        status: "acknowledged"
      }

      send(pid, {task.ref, {:ok, %{content: action_map}, Puck.Context.new()}})

      state = :sys.get_state(pid)

      assert state.notifications[notification.id].status == :acknowledged
      refute Map.has_key?(state.notifications, "nonexistent_id")

      stop_coordinator(pid)
    end
  end

  describe "handle_action - ProduceInsight" do
    test "auto-resolves referenced notifications" do
      {:ok, pid} = start_coordinator()

      notification1 = build_test_notification(%{anomaly_type: "type1"})
      notification2 = build_test_notification(%{anomaly_type: "type2"})
      task = Task.async(fn -> :ok end)
      Task.await(task)

      :sys.replace_state(pid, fn state ->
        notifications = %{
          notification1.id => %{notification: notification1, status: :acknowledged},
          notification2.id => %{notification: notification2, status: :acknowledged}
        }

        %{state | notifications: notifications, running: true, pending_task: task}
      end)

      action_map = %{
        intent: "produce_insight",
        notification_ids: [notification1.id, notification2.id],
        correlation_type: "causal",
        summary: "Test correlation",
        confidence: "high"
      }

      send(pid, {task.ref, {:ok, %{content: action_map}, Puck.Context.new()}})

      state = :sys.get_state(pid)

      assert state.notifications[notification1.id].status == :resolved
      assert state.notifications[notification2.id].status == :resolved

      stop_coordinator(pid)
    end

    test "adds insight_produced to context" do
      {:ok, pid} = start_coordinator()

      notification = build_test_notification()
      task = Task.async(fn -> :ok end)
      Task.await(task)

      :sys.replace_state(pid, fn state ->
        notifications = %{notification.id => %{notification: notification, status: :acknowledged}}
        %{state | notifications: notifications, running: true, pending_task: task}
      end)

      action_map = %{
        intent: "produce_insight",
        notification_ids: [notification.id],
        correlation_type: "temporal",
        summary: "Test insight",
        root_cause_hypothesis: "Test hypothesis",
        confidence: "medium"
      }

      send(pid, {task.ref, {:ok, %{content: action_map}, Puck.Context.new()}})

      state = :sys.get_state(pid)

      last_message = List.last(state.context.messages)
      content_text = extract_content_text(last_message.content)
      assert content_text =~ "insight_produced"

      stop_coordinator(pid)
    end
  end

  describe "handle_action - Done" do
    test "stops loop when no unread notifications" do
      {:ok, pid} = start_coordinator()

      notification = build_test_notification()
      task = Task.async(fn -> :ok end)
      Task.await(task)

      :sys.replace_state(pid, fn state ->
        notifications = %{notification.id => %{notification: notification, status: :resolved}}
        %{state | notifications: notifications, running: true, pending_task: task}
      end)

      action_map = %{intent: "done"}
      send(pid, {task.ref, {:ok, %{content: action_map}, Puck.Context.new()}})

      state = :sys.get_state(pid)

      assert state.running == false

      stop_coordinator(pid)
    end

    test "resets iteration when unread notifications exist" do
      ref = make_ref()
      parent = self()

      :telemetry.attach(
        {ref, :done},
        [:beamlens, :coordinator, :done],
        fn _event, _measurements, metadata, _ ->
          send(parent, {:telemetry, :done, metadata})
        end,
        nil
      )

      {:ok, pid} = start_coordinator()

      notification = build_test_notification()
      task = Task.async(fn -> :ok end)
      Task.await(task)

      :sys.replace_state(pid, fn state ->
        notifications = %{notification.id => %{notification: notification, status: :unread}}
        %{state | notifications: notifications, running: true, pending_task: task, iteration: 5}
      end)

      action_map = %{intent: "done"}
      send(pid, {task.ref, {:ok, %{content: action_map}, Puck.Context.new()}})

      assert_receive {:telemetry, :done, %{has_unread: true}}, 1000

      stop_coordinator(pid)
      :telemetry.detach({ref, :done})
    end
  end

  describe "error handling" do
    test "LLM error stops loop" do
      ref = make_ref()
      parent = self()

      :telemetry.attach(
        {ref, :llm_error},
        [:beamlens, :coordinator, :llm_error],
        fn _event, _measurements, metadata, _ ->
          send(parent, {:telemetry, :llm_error, metadata})
        end,
        nil
      )

      {:ok, pid} = start_coordinator()

      task = Task.async(fn -> :ok end)
      Task.await(task)

      :sys.replace_state(pid, fn state ->
        %{state | running: true, pending_task: task, pending_trace_id: "test-trace"}
      end)

      send(pid, {task.ref, {:error, :test_error}})

      assert_receive {:telemetry, :llm_error, %{reason: :test_error}}, 1000

      state = :sys.get_state(pid)
      assert state.running == false

      stop_coordinator(pid)
      :telemetry.detach({ref, :llm_error})
    end

    test "task crash handled gracefully" do
      ref = make_ref()
      parent = self()

      :telemetry.attach(
        {ref, :llm_error},
        [:beamlens, :coordinator, :llm_error],
        fn _event, _measurements, metadata, _ ->
          send(parent, {:telemetry, :llm_error, metadata})
        end,
        nil
      )

      {:ok, pid} = start_coordinator()

      task = Task.async(fn -> :ok end)
      Task.await(task)

      :sys.replace_state(pid, fn state ->
        %{state | running: true, pending_task: task, pending_trace_id: "test-trace"}
      end)

      send(pid, {:DOWN, task.ref, :process, task.pid, :killed})

      assert_receive {:telemetry, :llm_error, %{reason: {:task_crashed, :killed}}}, 1000

      state = :sys.get_state(pid)
      assert state.running == false

      stop_coordinator(pid)
      :telemetry.detach({ref, :llm_error})
    end
  end

  describe "telemetry events" do
    test "emits started event on init" do
      ref = make_ref()
      parent = self()

      :telemetry.attach(
        {ref, :started},
        [:beamlens, :coordinator, :started],
        fn _event, _measurements, metadata, _ ->
          send(parent, {:telemetry, :started, metadata})
        end,
        nil
      )

      {:ok, pid} =
        Coordinator.start_link(name: :"test_coord_#{:erlang.unique_integer([:positive])}")

      assert_receive {:telemetry, :started, %{running: false, notification_count: 0}}, 1000

      stop_coordinator(pid)
      :telemetry.detach({ref, :started})
    end

    test "emits notification_received event" do
      ref = make_ref()
      parent = self()

      :telemetry.attach(
        {ref, :notification_received},
        [:beamlens, :coordinator, :notification_received],
        fn _event, _measurements, metadata, _ ->
          send(parent, {:telemetry, :notification_received, metadata})
        end,
        nil
      )

      {:ok, pid} = start_coordinator()

      :sys.replace_state(pid, fn state ->
        %{state | running: true}
      end)

      notification = build_test_notification()
      simulate_notification(pid, notification)

      assert_receive {:telemetry, :notification_received, %{notification_id: _, operator: :test}},
                     1000

      stop_coordinator(pid)
      :telemetry.detach({ref, :notification_received})
    end

    test "emits iteration_start event when loop runs" do
      ref = make_ref()
      parent = self()

      :telemetry.attach(
        {ref, :iteration_start},
        [:beamlens, :coordinator, :iteration_start],
        fn _event, _measurements, metadata, _ ->
          send(parent, {:telemetry, :iteration_start, metadata})
        end,
        nil
      )

      {:ok, pid} = start_coordinator()

      notification = build_test_notification()
      simulate_notification(pid, notification)

      assert_receive {:telemetry, :iteration_start, %{iteration: 0, trace_id: _}}, 1000

      stop_coordinator(pid)
      :telemetry.detach({ref, :iteration_start})
    end

    test "emits insight_produced event" do
      ref = make_ref()
      parent = self()

      :telemetry.attach(
        {ref, :insight_produced},
        [:beamlens, :coordinator, :insight_produced],
        fn _event, _measurements, metadata, _ ->
          send(parent, {:telemetry, :insight_produced, metadata})
        end,
        nil
      )

      {:ok, pid} = start_coordinator()

      notification = build_test_notification()
      task = Task.async(fn -> :ok end)
      Task.await(task)

      :sys.replace_state(pid, fn state ->
        notifications = %{notification.id => %{notification: notification, status: :acknowledged}}

        %{
          state
          | notifications: notifications,
            running: true,
            pending_task: task,
            pending_trace_id: "test-trace"
        }
      end)

      action_map = %{
        intent: "produce_insight",
        notification_ids: [notification.id],
        correlation_type: "temporal",
        summary: "Test insight",
        confidence: "low"
      }

      send(pid, {task.ref, {:ok, %{content: action_map}, Puck.Context.new()}})

      assert_receive {:telemetry, :insight_produced, %{insight: %Insight{}}}, 1000

      stop_coordinator(pid)
      :telemetry.detach({ref, :insight_produced})
    end

    test "emits done event" do
      ref = make_ref()
      parent = self()

      :telemetry.attach(
        {ref, :done},
        [:beamlens, :coordinator, :done],
        fn _event, _measurements, metadata, _ ->
          send(parent, {:telemetry, :done, metadata})
        end,
        nil
      )

      {:ok, pid} = start_coordinator()

      task = Task.async(fn -> :ok end)
      Task.await(task)

      :sys.replace_state(pid, fn state ->
        %{state | running: true, pending_task: task, pending_trace_id: "test-trace"}
      end)

      action_map = %{intent: "done"}
      send(pid, {task.ref, {:ok, %{content: action_map}, Puck.Context.new()}})

      assert_receive {:telemetry, :done, %{has_unread: false}}, 1000

      stop_coordinator(pid)
      :telemetry.detach({ref, :done})
    end
  end

  describe "compaction configuration" do
    defp start_coordinator_for_compaction_test(opts \\ []) do
      name =
        Keyword.get(opts, :name, :"coordinator_compaction_#{:erlang.unique_integer([:positive])}")

      opts = Keyword.put(opts, :name, name)
      Coordinator.start_link(opts)
    end

    test "uses default compaction settings when not specified" do
      {:ok, pid} = start_coordinator_for_compaction_test()

      state = :sys.get_state(pid)
      client = state.client

      assert client.auto_compaction != nil
      {:summarize, config} = client.auto_compaction
      assert Keyword.get(config, :max_tokens) == 50_000
      assert Keyword.get(config, :keep_last) == 5
      assert is_binary(Keyword.get(config, :prompt))

      stop_coordinator(pid)
    end

    test "uses custom compaction_max_tokens when provided" do
      {:ok, pid} = start_coordinator_for_compaction_test(compaction_max_tokens: 100_000)

      state = :sys.get_state(pid)
      {:summarize, config} = state.client.auto_compaction
      assert Keyword.get(config, :max_tokens) == 100_000

      stop_coordinator(pid)
    end

    test "uses custom compaction_keep_last when provided" do
      {:ok, pid} = start_coordinator_for_compaction_test(compaction_keep_last: 10)

      state = :sys.get_state(pid)
      {:summarize, config} = state.client.auto_compaction
      assert Keyword.get(config, :keep_last) == 10

      stop_coordinator(pid)
    end

    test "uses both custom compaction settings when provided" do
      {:ok, pid} =
        start_coordinator_for_compaction_test(
          compaction_max_tokens: 75_000,
          compaction_keep_last: 8
        )

      state = :sys.get_state(pid)
      {:summarize, config} = state.client.auto_compaction

      assert Keyword.get(config, :max_tokens) == 75_000
      assert Keyword.get(config, :keep_last) == 8

      stop_coordinator(pid)
    end

    test "compaction prompt mentions notification analysis context" do
      {:ok, pid} = start_coordinator_for_compaction_test()

      state = :sys.get_state(pid)
      {:summarize, config} = state.client.auto_compaction
      prompt = Keyword.get(config, :prompt)

      assert prompt =~ "Notification IDs"
      assert prompt =~ "correlation"
      assert prompt =~ "Insights"

      stop_coordinator(pid)
    end
  end

  describe "pubsub integration" do
    setup do
      pubsub_name = :"TestPubSub_#{:erlang.unique_integer([:positive])}"
      {:ok, _} = start_supervised({Phoenix.PubSub, name: pubsub_name})
      %{pubsub: pubsub_name}
    end

    test "stores pubsub in state when provided", %{pubsub: pubsub} do
      name = :"coordinator_pubsub_#{:erlang.unique_integer([:positive])}"
      {:ok, pid} = Coordinator.start_link(name: name, pubsub: pubsub)

      :sys.replace_state(pid, fn state ->
        %{state | client: mock_client()}
      end)

      state = :sys.get_state(pid)
      assert state.pubsub == pubsub

      stop_coordinator(pid)
    end

    test "subscribes to pubsub topic on init", %{pubsub: pubsub} do
      name = :"coordinator_pubsub_sub_#{:erlang.unique_integer([:positive])}"
      {:ok, pid} = Coordinator.start_link(name: name, pubsub: pubsub)

      :sys.replace_state(pid, fn state ->
        %{state | client: mock_client()}
      end)

      notification = build_test_notification()

      Phoenix.PubSub.broadcast(
        pubsub,
        "beamlens:notifications",
        {:beamlens_notification, notification, :other@node}
      )

      state = :sys.get_state(pid)
      assert Map.has_key?(state.notifications, notification.id)

      stop_coordinator(pid)
    end

    test "ignores notifications from local node", %{pubsub: pubsub} do
      name = :"coordinator_pubsub_local_#{:erlang.unique_integer([:positive])}"
      {:ok, pid} = Coordinator.start_link(name: name, pubsub: pubsub)

      :sys.replace_state(pid, fn state ->
        %{state | client: mock_client()}
      end)

      notification = build_test_notification()

      Phoenix.PubSub.broadcast(
        pubsub,
        "beamlens:notifications",
        {:beamlens_notification, notification, node()}
      )

      state = :sys.get_state(pid)
      refute Map.has_key?(state.notifications, notification.id)

      stop_coordinator(pid)
    end

    test "emits remote_notification_received telemetry for cross-node notifications", %{
      pubsub: pubsub
    } do
      ref = make_ref()
      parent = self()

      :telemetry.attach(
        {ref, :remote_notification},
        [:beamlens, :coordinator, :remote_notification_received],
        fn _event, _measurements, metadata, _ ->
          send(parent, {:telemetry, :remote_notification_received, metadata})
        end,
        nil
      )

      name = :"coordinator_pubsub_tel_#{:erlang.unique_integer([:positive])}"
      {:ok, pid} = Coordinator.start_link(name: name, pubsub: pubsub)

      :sys.replace_state(pid, fn state ->
        %{state | client: mock_client()}
      end)

      notification = build_test_notification()

      Phoenix.PubSub.broadcast(
        pubsub,
        "beamlens:notifications",
        {:beamlens_notification, notification, :other@node}
      )

      assert_receive {:telemetry, :remote_notification_received,
                      %{notification_id: _, operator: :test, source_node: :other@node}},
                     1000

      stop_coordinator(pid)
      :telemetry.detach({ref, :remote_notification})
    end

    test "starts loop when receiving first remote notification", %{pubsub: pubsub} do
      ref = make_ref()
      parent = self()

      :telemetry.attach(
        {ref, :iteration_start},
        [:beamlens, :coordinator, :iteration_start],
        fn _event, _measurements, metadata, _ ->
          send(parent, {:telemetry, :iteration_start, metadata})
        end,
        nil
      )

      name = :"coordinator_pubsub_loop_#{:erlang.unique_integer([:positive])}"
      {:ok, pid} = Coordinator.start_link(name: name, pubsub: pubsub)

      :sys.replace_state(pid, fn state ->
        %{state | client: mock_client()}
      end)

      notification = build_test_notification()

      Phoenix.PubSub.broadcast(
        pubsub,
        "beamlens:notifications",
        {:beamlens_notification, notification, :other@node}
      )

      assert_receive {:telemetry, :iteration_start, %{iteration: 0}}, 1000

      stop_coordinator(pid)
      :telemetry.detach({ref, :iteration_start})
    end
  end

  describe "takeover telemetry" do
    test "emits takeover event on :shutdown termination" do
      Process.flag(:trap_exit, true)

      ref = make_ref()
      parent = self()

      :telemetry.attach(
        {ref, :takeover},
        [:beamlens, :coordinator, :takeover],
        fn _event, _measurements, metadata, _ ->
          send(parent, {:telemetry, :takeover, metadata})
        end,
        nil
      )

      {:ok, pid} = start_coordinator()

      notification = build_test_notification()

      :sys.replace_state(pid, fn state ->
        notifications = %{notification.id => %{notification: notification, status: :unread}}
        %{state | notifications: notifications}
      end)

      GenServer.stop(pid, :shutdown)

      assert_receive {:telemetry, :takeover, %{notification_count: 1}}, 1000

      :telemetry.detach({ref, :takeover})
    end

    test "does not emit takeover event on normal termination" do
      ref = make_ref()
      parent = self()

      :telemetry.attach(
        {ref, :takeover},
        [:beamlens, :coordinator, :takeover],
        fn _event, _measurements, metadata, _ ->
          send(parent, {:telemetry, :takeover, metadata})
        end,
        nil
      )

      {:ok, pid} = start_coordinator()
      GenServer.stop(pid, :normal)

      refute_receive {:telemetry, :takeover, _}, 100

      :telemetry.detach({ref, :takeover})
    end
  end
end
