// ============================================================================
// COORDINATOR AGENT TOOLS
// ============================================================================
// Notification correlation agent with 5 tools:
//
// - CoordinatorGetNotifications: Query notifications, optionally filtered by status
// - CoordinatorUpdateNotificationStatuses: Set status on multiple notifications
// - CoordinatorProduceInsight: Emit insight + auto-resolve referenced notifications
// - CoordinatorDone: End loop, wait for next notification
// - CoordinatorThink: Reason through complex decisions before acting
//
// Note: Message class is shared from operator.baml

class CoordinatorGetNotifications {
  intent "get_notifications"
  status "unread" | "acknowledged" | "resolved" | "all"? @description("Filter by status, default all")
}

class CoordinatorUpdateNotificationStatuses {
  intent "update_notification_statuses"
  notification_ids string[] @description("IDs of notifications to update")
  status "acknowledged" | "resolved" @description("New status for these notifications")
  reason string? @description("Optional reason for the status change")
}

class CoordinatorProduceInsight {
  intent "produce_insight"
  notification_ids string[] @description("IDs of notifications this insight correlates")
  correlation_type "temporal" | "causal" | "symptomatic" @description("How notifications are related")
  summary string @description("Brief explanation of the correlation")
  root_cause_hypothesis string? @description("Possible root cause if identified")
  confidence "high" | "medium" | "low" @description("Confidence in this correlation")
}

class CoordinatorDone {
  intent "done"
}

class CoordinatorThink {
  intent "think"
  thought string @description("Your reasoning about the current situation")
}

function CoordinatorLoop(messages: Message[], operator_descriptions: string) -> CoordinatorGetNotifications | CoordinatorUpdateNotificationStatuses | CoordinatorProduceInsight | CoordinatorDone | CoordinatorThink {
  client Default
  prompt #"
{{ _.role("system") }}
You are a notification correlation agent. You receive notifications from system operators
and identify patterns across them.

## Active Operators

{{ operator_descriptions }}

## Notification States
- unread: New notifications, not yet processed
- acknowledged: You're currently analyzing these
- resolved: Processed (correlated into insight or dismissed)

## Available Tools

### get_notifications(status?)
Query notifications. Filter by status or get all.

### update_notification_statuses(notification_ids, status, reason?)
Update status on multiple notifications.
- acknowledged: You're currently analyzing these
- resolved: Done processing (use for unrelated/false positives without insight)

### produce_insight(notification_ids, correlation_type, summary, root_cause_hypothesis?, confidence)
Create insight correlating notifications. Auto-resolves the referenced notifications.
- temporal: Notifications occurred close in time, possibly related
- causal: One notification directly caused another (A -> B)
- symptomatic: Notifications share a common hidden cause (A <- X -> B)

### done()
End processing. Call when finished with current notifications.

### think(thought)
Use this to reason through complex decisions before acting. Your thought
will be recorded but no action is taken. Good for:
- Analyzing notification patterns before correlating
- Working through ambiguous relationships
- Planning correlation strategy

## Guidelines
1. Start by getting unread notifications
2. Mark notifications as acknowledged before analyzing
3. Look for patterns: same operator, timing, related domains
4. Memory issues often cascade to scheduler/process problems
5. Produce insight for correlated notifications
6. Mark unrelated notifications as resolved (no insight needed)
7. Call done when finished

## Notification Age Considerations
- Pay attention to notification detected_at timestamps relative to current time
- Consider whether notifications are still relevant based on their age
- When correlating, prefer notifications with similar timestamps

{% for message in messages %}
{{ _.role(message.role) }}
{{ message.content }}
{% endfor %}

What action do you want to take?

{{ ctx.output_format }}
"#
}

// ============================================================================
// COORDINATOR TESTS
// ============================================================================

test CoordinatorLoop_GetsNotificationsFirst {
  functions [CoordinatorLoop]
  args {
    messages [
      { role "user", content "Process notifications" }
    ]
    operator_descriptions "- beam: BEAM VM health: memory, processes, schedulers, atoms"
  }
  @@assert(gets_notifications, {{ this.intent == "get_notifications" }})
}

test CoordinatorLoop_AcknowledgesUnreadNotifications {
  functions [CoordinatorLoop]
  args {
    messages [
      { role "user", content "Process notifications" },
      { role "user", content #"[{"id":"a1","status":"unread","operator":"beam","anomaly_type":"memory_elevated","severity":"warning","summary":"Memory at 78%","detected_at":"2024-01-06T10:30:00Z"},{"id":"a2","status":"unread","operator":"beam","anomaly_type":"scheduler_contention","severity":"warning","summary":"Run queue at 45","detected_at":"2024-01-06T10:30:30Z"}]"# }
    ]
    operator_descriptions "- beam: BEAM VM health: memory, processes, schedulers, atoms"
  }
  @@assert(acknowledges_first, {{ (this.intent == "update_notification_statuses" and this.status == "acknowledged") or this.intent == "think" }})
}

test CoordinatorLoop_ResolvesFalsePositive {
  functions [CoordinatorLoop]
  args {
    messages [
      { role "user", content "Process notifications" },
      { role "user", content #"[{"id":"a1","status":"acknowledged","operator":"beam","anomaly_type":"memory_elevated","severity":"info","summary":"Brief memory spike, returned to normal - no action needed","detected_at":"2024-01-06T10:30:00Z"}]"# }
    ]
    operator_descriptions "- beam: BEAM VM health: memory, processes, schedulers, atoms"
  }
  @@assert(resolves_false_positive, {{ (this.intent == "update_notification_statuses" and this.status == "resolved") or this.intent == "think" }})
}

test CoordinatorLoop_CompletesWhenDone {
  functions [CoordinatorLoop]
  args {
    messages [
      { role "user", content "Process notifications" },
      { role "assistant", content #"{"intent":"get_notifications","status":"unread"}"# },
      { role "user", content "No unread notifications found: []" }
    ]
    operator_descriptions "- beam: BEAM VM health: memory, processes, schedulers, atoms"
  }
  @@assert(calls_done, {{ this.intent == "done" or this.intent == "think" }})
}
