defmodule Beamlens.Watchers.StatusTest do
  use ExUnit.Case, async: true

  alias Beamlens.Watchers.Status

  describe "Status struct" do
    test "creates struct with required keys" do
      status = %Status{
        watcher: :beam,
        cron: "*/5 * * * *",
        run_count: 0,
        running: false
      }

      assert status.watcher == :beam
      assert status.cron == "*/5 * * * *"
      assert status.run_count == 0
      assert status.running == false
      assert status.next_run_at == nil
      assert status.last_run_at == nil
      assert status.name == nil
    end

    test "enforces required keys" do
      assert_raise ArgumentError, fn ->
        struct!(Status, [])
      end

      assert_raise ArgumentError, fn ->
        struct!(Status, watcher: :beam)
      end

      assert_raise ArgumentError, fn ->
        struct!(Status, watcher: :beam, cron: "* * * * *")
      end
    end

    test "accepts optional fields" do
      now = NaiveDateTime.utc_now()

      status = %Status{
        watcher: :beam,
        cron: "*/5 * * * *",
        run_count: 5,
        running: true,
        next_run_at: now,
        last_run_at: now,
        name: :my_watcher
      }

      assert status.next_run_at == now
      assert status.last_run_at == now
      assert status.name == :my_watcher
    end
  end
end
