defmodule Beamlens.Skill.System do
  @moduledoc """
  OS-level system metrics skill.

  Provides callback functions for collecting CPU, memory, and disk metrics
  from the operating system via Erlang's os_mon application.

  ## Requirements

  This skill requires os_mon to be started. Add it to your application's
  extra_applications in mix.exs:

      def application do
        [extra_applications: [:logger, :os_mon]]
      end

  ## Platform Notes

  - `cpu_sup` metrics are only available on Unix systems
  - `memsup` and `disksup` work on Unix and Windows

  All functions are read-only with zero side effects.
  """

  @behaviour Beamlens.Skill

  @compile {:no_warn_undefined, [:cpu_sup, :memsup, :disksup]}

  @impl true
  def id, do: :system

  @impl true
  def description, do: "OS resources: CPU load, system memory, disk usage"

  @impl true
  def system_prompt do
    """
    You are an OS-level system monitor. You track CPU, memory, and disk resources
    at the operating system level to detect host-level issues affecting the BEAM.

    ## Your Domain
    - CPU load averages (1m, 5m, 15m)
    - System memory usage and availability
    - Disk space utilization per mount point

    ## What to Watch For
    - CPU load > number of cores: system under pressure
    - Memory used > 85%: risk of OOM killer intervention
    - Disk usage > 90%: risk of write failures
    - Rising load averages: sustained pressure trend
    - Memory pressure without BEAM memory growth: external process competition
    """
  end

  @impl true
  def snapshot do
    mem = memory_stats()

    %{
      cpu_load_1m: cpu_load(:avg1),
      cpu_load_5m: cpu_load(:avg5),
      cpu_load_15m: cpu_load(:avg15),
      memory_used_pct: mem.used_pct,
      disk_max_used_pct: highest_disk_usage_pct()
    }
  end

  @impl true
  def callbacks do
    %{
      "system_get_cpu" => &cpu_stats/0,
      "system_get_memory" => &memory_stats/0,
      "system_get_disks" => &disk_stats/0
    }
  end

  @impl true
  def callback_docs do
    """
    ### system_get_cpu()
    CPU load averages: load_1m, load_5m, load_15m (normalized where 1.0 = 100% of one CPU),
    process_count (OS processes, not BEAM)

    ### system_get_memory()
    System memory: total_mb, used_mb, free_mb, used_pct, buffered_mb, cached_mb

    ### system_get_disks()
    Disk usage per mount point: list of {mount, total_mb, used_pct}
    """
  end

  defp cpu_stats do
    %{
      load_1m: cpu_load(:avg1),
      load_5m: cpu_load(:avg5),
      load_15m: cpu_load(:avg15),
      process_count: cpu_call(:nprocs)
    }
  end

  defp memory_stats do
    data = :memsup.get_system_memory_data()
    total = Keyword.get(data, :total_memory, 0)
    free = Keyword.get(data, :free_memory, 0)
    available = Keyword.get(data, :available_memory, free)
    used = total - available

    %{
      total_mb: bytes_to_mb(total),
      available_mb: bytes_to_mb(available),
      free_mb: bytes_to_mb(free),
      used_mb: bytes_to_mb(used),
      used_pct: percentage(used, total),
      buffered_mb: bytes_to_mb(Keyword.get(data, :buffered_memory, 0)),
      cached_mb: bytes_to_mb(Keyword.get(data, :cached_memory, 0))
    }
  end

  defp disk_stats do
    :disksup.get_disk_data()
    |> Enum.filter(&relevant_disk?/1)
    |> Enum.map(fn {mount, total_kb, used_pct} ->
      %{
        mount: to_string(mount),
        total_mb: Float.round(total_kb / 1024, 1),
        used_pct: used_pct
      }
    end)
  end

  defp relevant_disk?({mount, _total_kb, _pct}) do
    path = to_string(mount)
    not String.contains?(path, ["CoreSimulator", "Xcode", "TimeMachine", "/private/var/vm"])
  end

  defp cpu_load(avg_fun) do
    case Process.whereis(:cpu_sup) do
      nil -> 0.0
      _pid -> Float.round(apply(:cpu_sup, avg_fun, []) / 256, 2)
    end
  end

  defp cpu_call(fun) do
    case Process.whereis(:cpu_sup) do
      nil -> 0
      _pid -> apply(:cpu_sup, fun, [])
    end
  end

  defp highest_disk_usage_pct do
    :disksup.get_disk_data()
    |> Enum.filter(&relevant_disk?/1)
    |> pick_disk_pct()
  end

  defp pick_disk_pct([]), do: 0

  defp pick_disk_pct(disks) do
    case Enum.find(disks, fn {m, _, _} -> List.to_string(m) == "/" end) do
      {_, _, pct} -> pct
      nil -> disks |> Enum.max_by(&elem(&1, 2)) |> elem(2)
    end
  end

  defp percentage(_used, 0), do: 0.0
  defp percentage(used, total), do: Float.round(used / total * 100, 1)

  defp bytes_to_mb(bytes), do: Float.round(bytes / 1_048_576, 2)
end
