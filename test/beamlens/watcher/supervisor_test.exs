defmodule Beamlens.Watcher.SupervisorTest do
  @moduledoc false

  use ExUnit.Case

  alias Beamlens.Watcher.Supervisor, as: WatcherSupervisor

  defmodule TestDomain do
    @behaviour Beamlens.Domain

    def domain, do: :test_domain

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

    def callbacks, do: %{}
  end

  setup do
    start_supervised!({Registry, keys: :unique, name: Beamlens.WatcherRegistry})
    {:ok, supervisor} = WatcherSupervisor.start_link(name: nil)
    {:ok, supervisor: supervisor}
  end

  describe "start_watcher/2 with atom spec" do
    test "returns error for unknown builtin domain", %{supervisor: supervisor} do
      result = WatcherSupervisor.start_watcher(supervisor, :unknown)

      assert {:error, {:unknown_builtin_domain, :unknown}} = result
    end
  end

  describe "start_watcher/2 with keyword spec" do
    test "starts custom watcher without loop", %{supervisor: supervisor} do
      result =
        WatcherSupervisor.start_watcher(supervisor,
          name: :custom,
          domain_module: TestDomain,
          start_loop: false
        )

      assert {:ok, pid} = result
      assert Process.alive?(pid)
    end
  end

  describe "stop_watcher/2" do
    test "stops running watcher", %{supervisor: supervisor} do
      {:ok, pid} =
        WatcherSupervisor.start_watcher(supervisor,
          name: :to_stop,
          domain_module: TestDomain,
          start_loop: false
        )

      ref = Process.monitor(pid)
      result = WatcherSupervisor.stop_watcher(supervisor, :to_stop)

      assert :ok = result
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}
    end

    test "returns error for non-existent watcher", %{supervisor: supervisor} do
      result = WatcherSupervisor.stop_watcher(supervisor, :nonexistent)

      assert {:error, :not_found} = result
    end
  end

  describe "list_watchers/0" do
    test "returns empty list when no watchers", %{supervisor: _supervisor} do
      assert WatcherSupervisor.list_watchers() == []
    end

    test "returns list of watcher statuses", %{supervisor: supervisor} do
      WatcherSupervisor.start_watcher(supervisor,
        name: :watcher1,
        domain_module: TestDomain,
        start_loop: false
      )

      WatcherSupervisor.start_watcher(supervisor,
        name: :watcher2,
        domain_module: TestDomain,
        start_loop: false
      )

      watchers = WatcherSupervisor.list_watchers()

      assert length(watchers) == 2
      names = Enum.map(watchers, & &1.name)
      assert :watcher1 in names
      assert :watcher2 in names
    end
  end

  describe "watcher_status/1" do
    test "returns watcher status", %{supervisor: supervisor} do
      WatcherSupervisor.start_watcher(supervisor,
        name: :status_test,
        domain_module: TestDomain,
        start_loop: false
      )

      {:ok, status} = WatcherSupervisor.watcher_status(:status_test)

      assert status.watcher == :test_domain
      assert status.state == :healthy
    end

    test "returns error for non-existent watcher" do
      assert {:error, :not_found} = WatcherSupervisor.watcher_status(:nonexistent)
    end
  end

  describe "start_watcher/3 with client_registry" do
    test "passes client_registry to Watcher", %{supervisor: supervisor} do
      client_registry = %{primary: "Test", clients: []}

      {:ok, pid} =
        WatcherSupervisor.start_watcher(
          supervisor,
          [name: :registry_test, domain_module: TestDomain, start_loop: false],
          client_registry
        )

      state = :sys.get_state(pid)
      assert state.client_registry == client_registry
    end
  end
end
