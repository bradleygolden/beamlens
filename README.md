# beamlens

Autonomous supervision for the BEAM.

## The Problem

External tools like Datadog or Prometheus see your application from the outside. They tell you *that* memory is spiking, but not *why*.

To find the root cause, you might SSH in and attach an `iex` shell. By the time you do, the transient state—the stuck process, the bloated mailbox, the expensive query—is often gone.

## The Solution

beamlens is an Elixir library that runs inside your BEAM application. You add it to your own supervision tree, giving it the same access to the runtime that you would have. It observes your system from the inside, with full context of its live state.

## The Vision

BEAM applications that learn from themselves.

**Today: Observe and analyze.** beamlens monitors your system in real-time, correlates anomalies across domains, and produces actionable insights. When memory spikes, it doesn't just tell you—it investigates why, checking process heaps, ETS tables, and message queues to identify the root cause.

**Next: Execute with human-in-the-loop.** beamlens suggests specific actions based on what it finds. Kill a runaway process. Flush a bloated ETS table. Restart a stuck GenServer. You review and approve before anything happens.

**Already possible: Execute autonomously.** Custom skills can encode your runbooks. beamlens detects the anomaly, diagnoses the cause, and applies the fix—all while you sleep.

**The ultimate goal: Continuous self-improvement.** beamlens runs its own learning loop—observing what works, refining its understanding, and improving its own behavior over time. The system doesn't just heal itself; it gets better at healing itself.

The BEAM is uniquely suited for this future. Hot code reloading means fixes can be applied without restarts. Process isolation means experiments are safe—a failed remediation crashes one process, not your application. Full runtime introspection means the AI sees everything you would see in an IEx shell. No other runtime offers this combination.

## How It Works

When you trigger an analysis, beamlens:

1. Spins up **operators**—LLM-driven agents that collect snapshots and investigate using **skills**
2. The **coordinator** correlates findings across operators and produces **insights**
3. Results are returned or emitted via telemetry

**Skills** are Elixir behaviours that expose domain-specific state (memory, processes, ETS tables, etc.) to operators. Tool execution is sandboxed in Lua by default.

**Data Privacy**: You choose your own LLM provider. Telemetry data is processed within your infrastructure and is never sent to beamlens.

## Installation

```elixir
def deps do
  [{:beamlens, "~> 0.1.0"}]
end
```

## Quick Start

Add beamlens to your supervision tree in `application.ex`:

```elixir
def start(_type, _args) do
  children = [
    # ... your other children
    Beamlens
  ]

  Supervisor.start_link(children, strategy: :one_for_one)
end
```

Configure a [provider](docs/providers.md) or use the default Anthropic one by setting your API key:

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
```

Trigger an investigation (from an alert handler, Oban job, or IEx):

```elixir
{:ok, result} = Beamlens.Coordinator.run(%{reason: "memory alert triggered"},
  skills: [:beam, :ets, :system]
)

# The coordinator invokes operators, correlates findings, returns insights
result.insights
```

The `skills` option defines which operators are *available* to the coordinator. The LLM decides which to actually invoke based on the investigation context—it may use one, some, or all depending on relevance.

### Pre-configured Operators

For continuous monitoring or consistent operator sets, configure operators at startup:

```elixir
children = [
  {Beamlens, operators: [
    [name: :beam, skill: Beamlens.Skill.Beam, mode: :on_demand],
    [name: :ets, skill: Beamlens.Skill.Ets, mode: :on_demand]
  ]}
]
```

With pre-configured operators, `Coordinator.run/2` uses them automatically:

```elixir
{:ok, result} = Beamlens.Coordinator.run(%{reason: "memory alert"})
# Uses configured :beam and :ets operators
```

### Direct Operator Analysis

For targeted investigation of a single domain:

```elixir
{:ok, notifications} = Beamlens.Operator.run(:beam, %{reason: "scheduler contention"})
```

## Continuous Mode

For always-on monitoring, operators can run continuously in your supervision tree. The LLM controls timing via `wait()` between iterations.

```elixir
{Beamlens, operators: [[name: :beam, skill: Beamlens.Skill.Beam, mode: :continuous]]}
```

> **Cost Warning**: In continuous mode, operators choose their own polling interval via `wait()`. Based on ~30-second average pauses, running all core skills continuously with Haiku costs approximately **$1,000/month**—actual costs will vary depending on your runtime. Use on-demand analysis for cost-effective monitoring.

## Built-in Skills

| Skill | Description |
|-------|-------------|
| `:beam` | BEAM VM metrics (memory, processes, schedulers, atoms) |
| `:ets` | ETS table monitoring (counts, memory, largest tables) |
| `:gc` | Garbage collection statistics |
| `:logger` | Application log monitoring (error rates, patterns) |
| `:ports` | Port monitoring (file descriptors, sockets) |
| `:sup` | Supervisor tree monitoring |
| `:system` | OS-level metrics (CPU, memory, disk via `os_mon`) |

Add the skills you need to your `operators` list. The coordinator invokes configured operators during analysis.

## Creating Custom Skills

Implement the `Beamlens.Skill` behaviour to monitor your own domains:

```elixir
defmodule MyApp.Skills.Redis do
  @behaviour Beamlens.Skill

  @impl true
  def id, do: :redis

  @impl true
  def title, do: "Redis Cache"

  @impl true
  def description, do: "Redis cache: hit rates, memory, key distribution"

  @impl true
  def system_prompt do
    """
    You are a Redis cache monitor. You track cache health, memory usage,
    and key distribution patterns.

    ## Your Domain
    - Cache hit rates and efficiency
    - Memory usage and eviction pressure

    ## What to Watch For
    - Hit rate < 90%: cache may be ineffective
    - Memory usage > 80%: eviction pressure increasing
    """
  end

  @impl true
  def snapshot do
    %{
      connected: Redix.command!(:redix, ["PING"]) == "PONG",
      memory_used_mb: get_memory_mb(),
      connected_clients: get_client_count()
    }
  end

  @impl true
  def callbacks do
    %{
      "redis_info" => fn -> get_info() end,
      "redis_slowlog" => fn count -> get_slowlog(count) end
    }
  end

  @impl true
  def callback_docs do
    """
    ### redis_info()
    Full Redis INFO as a map.

    ### redis_slowlog(count)
    Recent slow queries. `count` limits results.
    """
  end

  defp get_info, do: # ...
  defp get_slowlog(count), do: # ...
  defp get_memory_mb, do: # ...
  defp get_client_count, do: # ...
end
```

Register your skill in application.ex:

```elixir
children = [
  {Beamlens, operators: [[name: :redis, skill: MyApp.Skills.Redis]]}
]
```

**Guidelines:**

- Write a clear `system_prompt`—it defines the operator's identity and focus
- Prefix callbacks with your skill name (`redis_info`, not `info`)
- Return JSON-safe values (strings, numbers, booleans, lists, maps)
- Keep snapshots fast—they're called frequently
- Write clear `callback_docs`—the LLM uses them to understand your API

All skills automatically have access to base callbacks from `Beamlens.Skill.Base`:
- `get_current_time()` — Returns current UTC timestamp
- `get_node_info()` — Returns node name, uptime, and OS info

## Telemetry

Subscribe to notifications:

```elixir
:telemetry.attach("my-notifications", [:beamlens, :operator, :notification_sent], fn
  _event, _measurements, %{notification: notification}, _config ->
    Logger.warning("beamlens: #{notification.summary}")
end, nil)
```

## Correlation Types

When the coordinator correlates notifications from multiple operators, it identifies patterns:

- **temporal** — Notifications occurred close in time
- **causal** — One notification caused another
- **symptomatic** — Notifications share a common hidden cause

## License

Apache-2.0
