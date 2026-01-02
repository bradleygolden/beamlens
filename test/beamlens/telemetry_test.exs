defmodule Beamlens.TelemetryTest do
  use ExUnit.Case

  describe "status_from_report/1" do
    test "returns :healthy for healthy status" do
      assert Beamlens.Telemetry.status_from_report(%{status: "healthy"}) == :healthy
    end

    test "returns :warning for warning status" do
      assert Beamlens.Telemetry.status_from_report(%{status: "warning"}) == :warning
    end

    test "returns :critical for critical status" do
      assert Beamlens.Telemetry.status_from_report(%{status: "critical"}) == :critical
    end

    test "returns :unknown for unrecognized status" do
      assert Beamlens.Telemetry.status_from_report(%{status: "other"}) == :unknown
      assert Beamlens.Telemetry.status_from_report(%{}) == :unknown
      assert Beamlens.Telemetry.status_from_report(nil) == :unknown
    end
  end

  describe "span/2" do
    test "emits start and stop events" do
      ref = make_ref()
      test_pid = self()

      :telemetry.attach_many(
        "test-handler-#{inspect(ref)}",
        [
          [:beamlens, :agent, :start],
          [:beamlens, :agent, :stop]
        ],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      result =
        Beamlens.Telemetry.span(%{node: "test@node"}, fn ->
          {:my_result, %{}, %{custom: "metadata"}}
        end)

      assert result == :my_result

      assert_receive {:telemetry, [:beamlens, :agent, :start], start_measurements, start_metadata}
      assert is_integer(start_measurements.system_time)
      assert start_metadata.node == "test@node"

      assert_receive {:telemetry, [:beamlens, :agent, :stop], stop_measurements, stop_metadata}
      assert is_integer(stop_measurements.duration)
      assert stop_metadata.custom == "metadata"

      :telemetry.detach("test-handler-#{inspect(ref)}")
    end

    test "emits exception event on error" do
      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "test-exception-handler-#{inspect(ref)}",
        [:beamlens, :agent, :exception],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      assert_raise RuntimeError, fn ->
        Beamlens.Telemetry.span(%{node: "test@node"}, fn ->
          raise "test error"
        end)
      end

      assert_receive {:telemetry, [:beamlens, :agent, :exception], measurements, metadata}
      assert is_integer(measurements.duration)
      assert metadata.kind == :error
      assert metadata.node == "test@node"

      :telemetry.detach("test-exception-handler-#{inspect(ref)}")
    end
  end
end
