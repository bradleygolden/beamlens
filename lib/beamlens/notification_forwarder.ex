defmodule Beamlens.NotificationForwarder do
  @moduledoc """
  Forwards local operator notifications to Phoenix PubSub for cross-node propagation.

  When running Beamlens in a cluster, notifications from operators on each node need
  to reach the Coordinator (which typically runs as a singleton). This module
  bridges that gap by subscribing to local telemetry events and broadcasting
  them to PubSub.

  ## Usage

  NotificationForwarder is automatically started when you provide a `:pubsub` option
  to the Beamlens supervisor:

      children = [
        {Beamlens,
          operators: [:beam, :ets],
          client_registry: client_registry(),
          pubsub: MyApp.PubSub}
      ]

  For advanced deployments, you can start it directly:

      children = [
        {Beamlens.NotificationForwarder, pubsub: MyApp.PubSub}
      ]

  ## PubSub Topic

  Notifications are broadcast to the topic `"beamlens:notifications"` with the message format:

      {:beamlens_notification, %Beamlens.Operator.Notification{}, source_node}

  """

  use GenServer

  @pubsub_topic "beamlens:notifications"
  @telemetry_handler_id "beamlens-notification-forwarder"

  @doc """
  Returns the PubSub topic used for notification broadcasts.
  """
  def pubsub_topic, do: @pubsub_topic

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end

  @impl true
  def init(opts) do
    pubsub = Keyword.fetch!(opts, :pubsub)

    :telemetry.attach(
      @telemetry_handler_id,
      [:beamlens, :operator, :notification_sent],
      &__MODULE__.handle_telemetry/4,
      %{pubsub: pubsub}
    )

    {:ok, %{pubsub: pubsub}}
  end

  @impl true
  def terminate(_reason, _state) do
    :telemetry.detach(@telemetry_handler_id)
    :ok
  end

  @doc false
  def handle_telemetry(_event, _measurements, %{notification: notification}, %{pubsub: pubsub}) do
    Phoenix.PubSub.broadcast(
      pubsub,
      @pubsub_topic,
      {:beamlens_notification, notification, node()}
    )
  end
end
