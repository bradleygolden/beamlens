defmodule BeamlensTest do
  use ExUnit.Case

  alias Beamlens.Collectors.Beam
  alias Beamlens.Tool

  describe "Beamlens.child_spec/1" do
    test "returns valid child spec" do
      spec = Beamlens.child_spec([])

      assert spec.id == Beamlens
      assert spec.start == {Beamlens, :start_link, [[]]}
      assert spec.type == :supervisor
    end

    test "passes options to start_link" do
      opts = [schedules: [{:default, "*/5 * * * *"}]]
      spec = Beamlens.child_spec(opts)

      assert spec.start == {Beamlens, :start_link, [opts]}
    end
  end

  describe "Beam collector tools/0" do
    test "returns list of 6 Tool structs" do
      tools = Beam.tools()

      assert length(tools) == 6
      assert Enum.all?(tools, &match?(%Tool{}, &1))
      assert Enum.all?(tools, &is_atom(&1.name))
      assert Enum.all?(tools, &is_binary(&1.intent))
      assert Enum.all?(tools, &is_binary(&1.description))
      assert Enum.all?(tools, &is_function(&1.execute, 0))
    end

    test "each tool has unique intent" do
      tools = Beam.tools()
      intents = Enum.map(tools, & &1.intent)

      assert intents == Enum.uniq(intents)
    end
  end

  describe "Beam collector - get_system_info tool" do
    setup do
      tool = find_tool("get_system_info")
      %{tool: tool}
    end

    test "returns expected structure", %{tool: tool} do
      info = tool.execute.()

      assert is_binary(info.node)
      assert is_binary(info.otp_release)
      assert is_binary(info.elixir_version)
      assert is_integer(info.uptime_seconds)
      assert is_integer(info.schedulers_online)
      assert info.schedulers_online > 0
    end

    test "is read-only (no side effects)", %{tool: tool} do
      i1 = tool.execute.()
      i2 = tool.execute.()

      assert Map.keys(i1) == Map.keys(i2)
      assert i1.node == i2.node
      assert i1.otp_release == i2.otp_release
      assert i1.elixir_version == i2.elixir_version
      assert i1.schedulers_online == i2.schedulers_online
    end
  end

  describe "Beam collector - get_memory_stats tool" do
    test "returns expected structure" do
      tool = find_tool("get_memory_stats")
      stats = tool.execute.()

      assert is_float(stats.total_mb)
      assert is_float(stats.processes_mb)
      assert is_float(stats.processes_used_mb)
      assert is_float(stats.system_mb)
      assert is_float(stats.binary_mb)
      assert is_float(stats.ets_mb)
      assert is_float(stats.code_mb)
    end
  end

  describe "Beam collector - get_process_stats tool" do
    test "returns expected structure" do
      tool = find_tool("get_process_stats")
      stats = tool.execute.()

      assert is_integer(stats.process_count)
      assert is_integer(stats.process_limit)
      assert is_integer(stats.port_count)
      assert is_integer(stats.port_limit)
      assert stats.process_count > 0
      assert stats.process_limit > stats.process_count
    end
  end

  describe "Beam collector - get_scheduler_stats tool" do
    test "returns expected structure" do
      tool = find_tool("get_scheduler_stats")
      stats = tool.execute.()

      assert is_integer(stats.schedulers)
      assert is_integer(stats.schedulers_online)
      assert is_integer(stats.dirty_cpu_schedulers_online)
      assert is_integer(stats.dirty_io_schedulers)
      assert is_integer(stats.run_queue)
      assert stats.schedulers >= stats.schedulers_online
    end
  end

  describe "Beam collector - get_atom_stats tool" do
    test "returns expected structure" do
      tool = find_tool("get_atom_stats")
      stats = tool.execute.()

      assert is_integer(stats.atom_count)
      assert is_integer(stats.atom_limit)
      assert is_float(stats.atom_mb)
      assert is_float(stats.atom_used_mb)
      assert stats.atom_count > 0
      assert stats.atom_limit > stats.atom_count
    end
  end

  describe "Beam collector - get_persistent_terms tool" do
    test "returns expected structure" do
      tool = find_tool("get_persistent_terms")
      stats = tool.execute.()

      assert is_integer(stats.count)
      assert is_float(stats.memory_mb)
      assert stats.count >= 0
    end
  end

  defp find_tool(intent) do
    Enum.find(Beam.tools(), fn tool -> tool.intent == intent end)
  end
end
