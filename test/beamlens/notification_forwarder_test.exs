defmodule Beamlens.NotificationForwarderTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Beamlens.NotificationForwarder
  alias Beamlens.Operator.Notification

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

  describe "pubsub_topic/0" do
    test "returns the expected topic" do
      assert NotificationForwarder.pubsub_topic() == "beamlens:notifications"
    end
  end

  describe "start_link/1" do
    test "starts with pubsub option" do
      pubsub_name = :"TestPubSub_start_#{:erlang.unique_integer([:positive])}"
      {:ok, _} = start_supervised({Phoenix.PubSub, name: pubsub_name})

      {:ok, pid} = NotificationForwarder.start_link(pubsub: pubsub_name)
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end

    test "fails to start when pubsub option missing" do
      Process.flag(:trap_exit, true)

      assert {:error, _} = NotificationForwarder.start_link([])
    end
  end

  describe "notification forwarding" do
    test "broadcasts notifications to pubsub when telemetry event fires" do
      pubsub_name = :"TestPubSub_broadcast_#{:erlang.unique_integer([:positive])}"
      {:ok, _} = Phoenix.PubSub.Supervisor.start_link(name: pubsub_name)

      {:ok, forwarder} = NotificationForwarder.start_link(pubsub: pubsub_name)
      Phoenix.PubSub.subscribe(pubsub_name, NotificationForwarder.pubsub_topic())

      notification = build_test_notification()

      :telemetry.execute(
        [:beamlens, :operator, :notification_sent],
        %{system_time: System.system_time()},
        %{notification: notification, operator: :test, trace_id: "test-trace"}
      )

      assert_receive {:beamlens_notification, received_notification, source_node}, 1000
      assert received_notification.id == notification.id
      assert source_node == node()

      GenServer.stop(forwarder)
    end
  end

  describe "terminate/2" do
    test "detaches telemetry handler on stop" do
      pubsub_name = :"TestPubSub_term_#{:erlang.unique_integer([:positive])}"
      {:ok, _} = start_supervised({Phoenix.PubSub, name: pubsub_name})

      {:ok, pid} = NotificationForwarder.start_link(pubsub: pubsub_name)

      handlers_before = :telemetry.list_handlers([:beamlens, :operator, :notification_sent])
      assert Enum.any?(handlers_before, &(&1.id == "beamlens-notification-forwarder"))

      GenServer.stop(pid)

      handlers_after = :telemetry.list_handlers([:beamlens, :operator, :notification_sent])
      refute Enum.any?(handlers_after, &(&1.id == "beamlens-notification-forwarder"))
    end
  end
end
