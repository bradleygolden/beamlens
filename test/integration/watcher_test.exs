defmodule Beamlens.Integration.WatcherTest do
  @moduledoc false

  use Beamlens.IntegrationCase, async: false

  alias Beamlens.Watcher

  defmodule TestDomain do
    @behaviour Beamlens.Domain

    def domain, do: :integration_test

    def snapshot do
      %{
        memory_utilization_pct: 45.0,
        process_utilization_pct: 10.0,
        port_utilization_pct: 5.0,
        atom_utilization_pct: 2.0,
        scheduler_run_queue: 0,
        schedulers_online: 8
      }
    end

    def callbacks do
      %{
        "get_memory" => fn -> %{total_mb: 100, used_mb: 45} end,
        "get_test_value" => fn -> 42 end
      }
    end
  end

  describe "watcher lifecycle" do
    @tag timeout: 30_000
    test "starts and emits iteration events", %{client_registry: client_registry} do
      ref = make_ref()
      parent = self()

      :telemetry.attach(
        ref,
        [:beamlens, :watcher, :iteration_start],
        fn _event, _measurements, metadata, _ ->
          send(parent, {:telemetry, :iteration_start, metadata})
        end,
        nil
      )

      {:ok, pid} =
        Watcher.start_link(
          domain_module: TestDomain,
          client_registry: client_registry
        )

      assert_receive {:telemetry, :iteration_start, %{watcher: :integration_test, iteration: 0}},
                     10_000

      status = Watcher.status(pid)
      assert status.watcher == :integration_test
      assert status.running == true

      Watcher.stop(pid)
      :telemetry.detach(ref)
    end

    @tag timeout: 60_000
    test "emits llm events during loop", %{client_registry: client_registry} do
      ref = make_ref()
      parent = self()

      :telemetry.attach(
        ref,
        [:beamlens, :llm, :start],
        fn _event, _measurements, metadata, _ ->
          send(parent, {:telemetry, :llm_start, metadata})
        end,
        nil
      )

      {:ok, pid} =
        Watcher.start_link(
          domain_module: TestDomain,
          client_registry: client_registry
        )

      assert_receive {:telemetry, :llm_start, %{trace_id: trace_id}}, 15_000
      assert is_binary(trace_id)

      Watcher.stop(pid)
      :telemetry.detach(ref)
    end

    @tag timeout: 60_000
    test "takes snapshot on first iteration per BAML prompt instructions", %{
      client_registry: client_registry
    } do
      ref = make_ref()
      parent = self()

      :telemetry.attach(
        ref,
        [:beamlens, :watcher, :take_snapshot],
        fn _event, _measurements, metadata, _ ->
          send(parent, {:telemetry, :take_snapshot, metadata})
        end,
        nil
      )

      {:ok, pid} =
        Watcher.start_link(
          domain_module: TestDomain,
          client_registry: client_registry
        )

      assert_receive {:telemetry, :take_snapshot,
                      %{watcher: :integration_test, snapshot_id: snapshot_id}},
                     30_000

      assert is_binary(snapshot_id)
      assert String.length(snapshot_id) == 16

      state = :sys.get_state(pid)
      assert state.snapshots != []

      Watcher.stop(pid)
      :telemetry.detach(ref)
    end
  end
end
