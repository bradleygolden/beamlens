defmodule BeamlensTest do
  use ExUnit.Case

  describe "Beamlens.Collector" do
    test "beam_metrics returns expected structure" do
      metrics = Beamlens.Collector.beam_metrics()

      assert is_binary(metrics.otp_release)
      assert is_integer(metrics.schedulers_online)
      assert metrics.schedulers_online > 0

      assert is_map(metrics.memory)
      assert is_float(metrics.memory.total_mb)
      assert is_float(metrics.memory.processes_mb)
      assert is_float(metrics.memory.atom_mb)
      assert is_float(metrics.memory.binary_mb)
      assert is_float(metrics.memory.ets_mb)

      assert is_integer(metrics.process_count)
      assert metrics.process_count > 0

      assert is_integer(metrics.port_count)
      assert is_integer(metrics.uptime_seconds)
      assert is_integer(metrics.run_queue)
    end

    test "beam_metrics is read-only (no side effects)" do
      # Call multiple times - should return consistent structure
      m1 = Beamlens.Collector.beam_metrics()
      m2 = Beamlens.Collector.beam_metrics()

      # Structure should be identical
      assert Map.keys(m1) == Map.keys(m2)
      assert Map.keys(m1.memory) == Map.keys(m2.memory)

      # OTP release shouldn't change
      assert m1.otp_release == m2.otp_release
      assert m1.schedulers_online == m2.schedulers_online
    end
  end
end
