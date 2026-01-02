# BeamLens

A minimal, safe AI agent that monitors BEAM VM health and generates analyses using Claude Haiku.

## Features

- **Safe by design**: Read-only metrics, no PII/PHI exposure, zero side effects
- **Pure Elixir**: Uses [Strider](https://github.com/bradleygolden/strider) + [BAML](https://github.com/boundaryml/baml) for type-safe LLM calls
- **Structured output**: Returns typed `HealthAnalysis` structs, not raw text
- **Periodic monitoring**: Runs health checks at configurable intervals
- **Claude-powered analysis**: Uses Haiku for cost-effective, intelligent analysis

## Installation

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:beamlens, github: "bradleygolden/beamlens"}
  ]
end
```

## Configuration

```bash
# Required environment variable
export ANTHROPIC_API_KEY=your-api-key
```

```elixir
# config/config.exs
config :beamlens,
  mode: :periodic,              # :periodic | :manual
  interval: :timer.minutes(5)
```

## Usage

### As a supervised process

```elixir
# In your application.ex
def start(_type, _args) do
  children = [
    # ... your other children
    {Beamlens, []}
  ]
  Supervisor.start_link(children, strategy: :one_for_one)
end
```

### Manual analysis

```elixir
{:ok, analysis} = Beamlens.run()

analysis.status          #=> :healthy
analysis.summary         #=> "BEAM VM is operating normally..."
analysis.concerns        #=> []
analysis.recommendations #=> []
```

## Telemetry

BeamLens emits telemetry events for observability:

| Event | Description |
|-------|-------------|
| `[:beamlens, :agent, :start]` | Agent run starting |
| `[:beamlens, :agent, :stop]` | Agent run completed |
| `[:beamlens, :agent, :exception]` | Agent run failed |

### Example handler

```elixir
:telemetry.attach("my-handler", [:beamlens, :agent, :stop],
  fn _event, %{duration: duration}, %{status: status, analysis: analysis}, _config ->
    Logger.info("BeamLens: #{status} in #{duration}ns")

    if status == :critical do
      MyApp.Alerts.send(analysis.summary)
    end
  end, nil)
```

## What it monitors

BeamLens gathers safe, read-only VM metrics:

- OTP release version
- Scheduler count and utilization (run queue)
- Memory breakdown (total, processes, atoms, binaries, ETS)
- Process and port counts
- System uptime

All data comes from `:erlang.system_info/1` and `:erlang.memory/0` - read-only calls with zero side effects.

## Security

- **Read-only**: No filesystem, shell, or write access
- **No PII/PHI**: Only aggregate VM statistics
- **Type-safe**: BAML ensures structured, validated responses
- **Supervised**: Automatic restart on failure
- **Cost controlled**: Uses Haiku (~$0.001/run)

## License

MIT
