defmodule Beamlens.Collector do
  @moduledoc """
  Gathers BEAM VM metrics safely.

  All functions are read-only with zero side effects.
  No PII/PHI exposure - only aggregate system statistics.
  """

  @doc """
  Returns current BEAM VM health metrics.

  All data comes from `:erlang.system_info/1` and `:erlang.memory/0`.
  These are read-only calls with zero side effects on the VM.
  """
  def beam_metrics do
    memory = :erlang.memory()

    %{
      otp_release: to_string(:erlang.system_info(:otp_release)),
      schedulers_online: :erlang.system_info(:schedulers_online),
      memory: %{
        total_mb: bytes_to_mb(memory[:total]),
        processes_mb: bytes_to_mb(memory[:processes]),
        atom_mb: bytes_to_mb(memory[:atom]),
        binary_mb: bytes_to_mb(memory[:binary]),
        ets_mb: bytes_to_mb(memory[:ets])
      },
      process_count: :erlang.system_info(:process_count),
      port_count: :erlang.system_info(:port_count),
      uptime_seconds: uptime_seconds(),
      run_queue: :erlang.statistics(:run_queue)
    }
  end

  defp bytes_to_mb(bytes), do: Float.round(bytes / 1_048_576, 2)

  defp uptime_seconds do
    {wall_clock_ms, _} = :erlang.statistics(:wall_clock)
    div(wall_clock_ms, 1000)
  end
end
