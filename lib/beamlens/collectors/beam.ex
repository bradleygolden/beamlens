defmodule Beamlens.Collectors.Beam do
  @moduledoc """
  BEAM VM collector providing core runtime metrics.

  All functions are read-only with zero side effects.
  No PII/PHI exposure - only aggregate system statistics.
  """

  @behaviour Beamlens.Collector

  alias Beamlens.Tool

  @impl true
  def tools do
    [
      %Tool{
        name: :system_info,
        intent: "get_system_info",
        description: "Get basic node context (always call first)",
        execute: &system_info/0
      },
      %Tool{
        name: :memory_stats,
        intent: "get_memory_stats",
        description: "Get detailed memory statistics for leak detection",
        execute: &memory_stats/0
      },
      %Tool{
        name: :process_stats,
        intent: "get_process_stats",
        description: "Get process/port counts and limits for capacity check",
        execute: &process_stats/0
      },
      %Tool{
        name: :scheduler_stats,
        intent: "get_scheduler_stats",
        description: "Get scheduler details and run queues for performance analysis",
        execute: &scheduler_stats/0
      },
      %Tool{
        name: :atom_stats,
        intent: "get_atom_stats",
        description: "Get atom table metrics when suspecting atom leaks",
        execute: &atom_stats/0
      },
      %Tool{
        name: :persistent_terms,
        intent: "get_persistent_terms",
        description: "Get persistent term usage statistics",
        execute: &persistent_terms/0
      }
    ]
  end

  defp system_info do
    %{
      node: Atom.to_string(Node.self()),
      otp_release: to_string(:erlang.system_info(:otp_release)),
      elixir_version: System.version(),
      uptime_seconds: uptime_seconds(),
      schedulers_online: :erlang.system_info(:schedulers_online)
    }
  end

  defp memory_stats do
    memory = :erlang.memory()

    %{
      total_mb: bytes_to_mb(memory[:total]),
      processes_mb: bytes_to_mb(memory[:processes]),
      processes_used_mb: bytes_to_mb(memory[:processes_used]),
      system_mb: bytes_to_mb(memory[:system]),
      binary_mb: bytes_to_mb(memory[:binary]),
      ets_mb: bytes_to_mb(memory[:ets]),
      code_mb: bytes_to_mb(memory[:code])
    }
  end

  defp process_stats do
    %{
      process_count: :erlang.system_info(:process_count),
      process_limit: :erlang.system_info(:process_limit),
      port_count: :erlang.system_info(:port_count),
      port_limit: :erlang.system_info(:port_limit)
    }
  end

  defp scheduler_stats do
    %{
      schedulers: :erlang.system_info(:schedulers),
      schedulers_online: :erlang.system_info(:schedulers_online),
      dirty_cpu_schedulers_online: :erlang.system_info(:dirty_cpu_schedulers_online),
      dirty_io_schedulers: :erlang.system_info(:dirty_io_schedulers),
      run_queue: :erlang.statistics(:run_queue)
    }
  end

  defp atom_stats do
    memory = :erlang.memory()

    %{
      atom_count: :erlang.system_info(:atom_count),
      atom_limit: :erlang.system_info(:atom_limit),
      atom_mb: bytes_to_mb(memory[:atom]),
      atom_used_mb: bytes_to_mb(memory[:atom_used])
    }
  end

  defp persistent_terms do
    info = :persistent_term.info()

    %{
      count: info[:count],
      memory_mb: bytes_to_mb(info[:memory])
    }
  end

  defp bytes_to_mb(bytes), do: Float.round(bytes / 1_048_576, 2)

  defp uptime_seconds do
    {wall_clock_ms, _} = :erlang.statistics(:wall_clock)
    div(wall_clock_ms, 1000)
  end
end
