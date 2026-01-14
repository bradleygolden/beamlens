defmodule Beamlens.SupervisorTest do
  use ExUnit.Case, async: false

  describe "start_link/1 with client_registry" do
    test "starts supervisor with client_registry" do
      client_registry = %{primary: "Test", clients: []}

      {:ok, supervisor} =
        start_supervised({Beamlens.Supervisor, client_registry: client_registry, watchers: []})

      assert Process.alive?(supervisor)
    end
  end

  describe "quick start pattern" do
    test "lists configured operators" do
      {:ok, _supervisor} =
        start_supervised(
          {Beamlens,
           operators: [
             [name: :beam, skill: Beamlens.Skill.Beam],
             [name: :ets, skill: Beamlens.Skill.Ets],
             [name: :system, skill: Beamlens.Skill.System]
           ]}
        )

      # Verify operators are listed correctly
      operators = Beamlens.list_operators()

      assert length(operators) == 3
      assert Enum.all?(operators, &(&1.running == false))

      names = Enum.map(operators, & &1.name)
      assert :beam in names
      assert :ets in names
      assert :system in names

      # Verify each operator has expected structure (stopped until manually started)
      beam_op = Enum.find(operators, &(&1.name == :beam))
      assert beam_op.state == :stopped
      assert beam_op.title == "BEAM VM"
    end

    test "coordinator is started by supervisor" do
      {:ok, _supervisor} =
        start_supervised(
          {Beamlens,
           operators: [
             [name: :beam, skill: Beamlens.Skill.Beam]
           ]}
        )

      # Verify the supervisor-started coordinator is accessible
      status = Beamlens.Coordinator.status()

      assert status.running == false
      assert status.notification_count == 0
      assert status.iteration == 0
    end
  end
end
