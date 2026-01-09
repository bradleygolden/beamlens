defmodule Beamlens.Integration.SupervisorTest do
  @moduledoc false

  use Beamlens.IntegrationCase, async: false

  alias Beamlens.Watcher.Supervisor, as: WatcherSupervisor

  setup do
    start_supervised!({Registry, keys: :unique, name: Beamlens.WatcherRegistry})
    {:ok, supervisor} = WatcherSupervisor.start_link(name: nil)
    {:ok, supervisor: supervisor}
  end

  describe "start_watcher/2 with atom spec" do
    @tag timeout: 30_000
    test "starts builtin beam watcher", %{supervisor: supervisor} do
      result = WatcherSupervisor.start_watcher(supervisor, :beam)

      assert {:ok, pid} = result
      assert Process.alive?(pid)
    end
  end
end
