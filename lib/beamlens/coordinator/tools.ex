defmodule Beamlens.Coordinator.Tools do
  @moduledoc """
  Tool structs and union schema for the coordinator agent loop.

  Tools:
  - GetNotifications: Query notifications, optionally filtered by status
  - UpdateNotificationStatuses: Set status on multiple notifications
  - ProduceInsight: Emit insight + auto-resolve referenced notifications
  - Done: End loop, wait for next notification
  - Think: Reason through complex decisions before acting
  """

  defmodule GetNotifications do
    @moduledoc false
    defstruct [:intent, :status]

    @type t :: %__MODULE__{
            intent: String.t(),
            status: :unread | :acknowledged | :resolved | nil
          }
  end

  defmodule UpdateNotificationStatuses do
    @moduledoc false
    defstruct [:intent, :notification_ids, :status, :reason]

    @type t :: %__MODULE__{
            intent: String.t(),
            notification_ids: [String.t()],
            status: :acknowledged | :resolved,
            reason: String.t() | nil
          }
  end

  defmodule ProduceInsight do
    @moduledoc false
    defstruct [
      :intent,
      :notification_ids,
      :correlation_type,
      :summary,
      :root_cause_hypothesis,
      :confidence
    ]

    @type t :: %__MODULE__{
            intent: String.t(),
            notification_ids: [String.t()],
            correlation_type: :temporal | :causal | :symptomatic,
            summary: String.t(),
            root_cause_hypothesis: String.t() | nil,
            confidence: :high | :medium | :low
          }
  end

  defmodule Done do
    @moduledoc false
    defstruct [:intent]

    @type t :: %__MODULE__{intent: String.t()}
  end

  defmodule Think do
    @moduledoc false
    defstruct [:intent, :thought]

    @type t :: %__MODULE__{
            intent: String.t(),
            thought: String.t()
          }
  end

  @doc """
  Returns a Zoi union schema for parsing coordinator tool responses.

  Uses discriminated union pattern matching on the `intent` field.
  """
  def schema do
    Zoi.union([
      get_notifications_schema(),
      update_notification_statuses_schema(),
      produce_insight_schema(),
      done_schema(),
      think_schema()
    ])
  end

  defp get_notifications_schema do
    Zoi.object(%{
      intent: Zoi.literal("get_notifications"),
      status:
        Zoi.nullish(
          Zoi.enum(["unread", "acknowledged", "resolved", "all"])
          |> Zoi.transform(&atomize_status/1)
        )
    })
    |> Zoi.transform(fn data -> {:ok, struct!(GetNotifications, data)} end)
  end

  defp update_notification_statuses_schema do
    Zoi.object(%{
      intent: Zoi.literal("update_notification_statuses"),
      notification_ids: Zoi.list(Zoi.string()),
      status:
        Zoi.enum(["acknowledged", "resolved"])
        |> Zoi.transform(&atomize_status/1),
      reason: Zoi.nullish(Zoi.string())
    })
    |> Zoi.transform(fn data -> {:ok, struct!(UpdateNotificationStatuses, data)} end)
  end

  defp produce_insight_schema do
    Zoi.object(%{
      intent: Zoi.literal("produce_insight"),
      notification_ids: Zoi.list(Zoi.string()),
      correlation_type:
        Zoi.enum(["temporal", "causal", "symptomatic"])
        |> Zoi.transform(&atomize_correlation_type/1),
      summary: Zoi.string(),
      root_cause_hypothesis: Zoi.nullish(Zoi.string()),
      confidence:
        Zoi.enum(["high", "medium", "low"])
        |> Zoi.transform(&atomize_confidence/1)
    })
    |> Zoi.transform(fn data -> {:ok, struct!(ProduceInsight, data)} end)
  end

  defp done_schema do
    Zoi.object(%{intent: Zoi.literal("done")})
    |> Zoi.transform(fn data -> {:ok, struct!(Done, data)} end)
  end

  defp think_schema do
    Zoi.object(%{
      intent: Zoi.literal("think"),
      thought: Zoi.string()
    })
    |> Zoi.transform(fn data -> {:ok, struct!(Think, data)} end)
  end

  defp atomize_status("unread"), do: {:ok, :unread}
  defp atomize_status("acknowledged"), do: {:ok, :acknowledged}
  defp atomize_status("resolved"), do: {:ok, :resolved}
  defp atomize_status("all"), do: {:ok, nil}

  defp atomize_correlation_type("temporal"), do: {:ok, :temporal}
  defp atomize_correlation_type("causal"), do: {:ok, :causal}
  defp atomize_correlation_type("symptomatic"), do: {:ok, :symptomatic}

  defp atomize_confidence("high"), do: {:ok, :high}
  defp atomize_confidence("medium"), do: {:ok, :medium}
  defp atomize_confidence("low"), do: {:ok, :low}
end
