defmodule Beamlens.Collectors.BeamTest do
  use ExUnit.Case, async: true

  alias Beamlens.Collectors.Beam
  alias Beamlens.Tool

  describe "tools/0" do
    test "returns list of 8 Tool structs" do
      tools = Beam.tools()

      assert length(tools) == 8
      assert Enum.all?(tools, &match?(%Tool{}, &1))
      assert Enum.all?(tools, &is_atom(&1.name))
      assert Enum.all?(tools, &is_binary(&1.intent))
      assert Enum.all?(tools, &is_binary(&1.description))
      assert Enum.all?(tools, &is_function(&1.execute, 1))
    end

    test "each tool has unique intent" do
      tools = Beam.tools()
      intents = Enum.map(tools, & &1.intent)

      assert intents == Enum.uniq(intents)
    end
  end

  describe "snapshot/0" do
    test "returns all metric categories" do
      snapshot = Beam.snapshot()

      assert Map.has_key?(snapshot, :system_info)
      assert Map.has_key?(snapshot, :memory_stats)
      assert Map.has_key?(snapshot, :process_stats)
      assert Map.has_key?(snapshot, :scheduler_stats)
      assert Map.has_key?(snapshot, :atom_stats)
      assert Map.has_key?(snapshot, :persistent_terms)
      assert Map.has_key?(snapshot, :overview)
      assert Map.has_key?(snapshot, :top_processes)
    end

    test "top_processes contains up to 10 processes" do
      snapshot = Beam.snapshot()

      assert is_list(snapshot.top_processes.processes)
      assert snapshot.top_processes.limit == 10
    end

    test "overview contains pre-calculated percentages" do
      snapshot = Beam.snapshot()

      assert is_float(snapshot.overview.memory_utilization_pct)
      assert is_float(snapshot.overview.process_utilization_pct)
      assert is_integer(snapshot.overview.scheduler_run_queue)
    end

    test "encodes to JSON without error" do
      snapshot = Beam.snapshot()

      assert {:ok, json} = Jason.encode(snapshot)
      assert is_binary(json)
    end
  end

  describe "get_overview tool" do
    setup do
      tool = find_tool("get_overview")
      %{tool: tool}
    end

    test "returns expected structure", %{tool: tool} do
      overview = tool.execute.(%{})

      assert is_float(overview.memory_utilization_pct)
      assert is_float(overview.process_utilization_pct)
      assert is_float(overview.port_utilization_pct)
      assert is_float(overview.atom_utilization_pct)
      assert is_integer(overview.scheduler_run_queue)
      assert is_integer(overview.schedulers_online)
      assert overview.schedulers_online > 0
    end

    test "percentages are within valid range", %{tool: tool} do
      overview = tool.execute.(%{})

      assert overview.memory_utilization_pct >= 0.0
      assert overview.memory_utilization_pct <= 100.0
      assert overview.process_utilization_pct >= 0.0
      assert overview.process_utilization_pct <= 100.0
      assert overview.port_utilization_pct >= 0.0
      assert overview.port_utilization_pct <= 100.0
      assert overview.atom_utilization_pct >= 0.0
      assert overview.atom_utilization_pct <= 100.0
    end

    test "is read-only (no side effects)", %{tool: tool} do
      o1 = tool.execute.(%{})
      o2 = tool.execute.(%{})

      assert Map.keys(o1) == Map.keys(o2)
      assert o1.schedulers_online == o2.schedulers_online
    end
  end

  describe "get_system_info tool" do
    setup do
      tool = find_tool("get_system_info")
      %{tool: tool}
    end

    test "returns expected structure", %{tool: tool} do
      info = tool.execute.(%{})

      assert is_binary(info.node)
      assert is_binary(info.otp_release)
      assert is_binary(info.elixir_version)
      assert is_integer(info.uptime_seconds)
      assert is_integer(info.schedulers_online)
      assert info.schedulers_online > 0
    end

    test "is read-only (no side effects)", %{tool: tool} do
      i1 = tool.execute.(%{})
      i2 = tool.execute.(%{})

      assert Map.keys(i1) == Map.keys(i2)
      assert i1.node == i2.node
      assert i1.otp_release == i2.otp_release
      assert i1.elixir_version == i2.elixir_version
      assert i1.schedulers_online == i2.schedulers_online
    end
  end

  describe "get_memory_stats tool" do
    test "returns expected structure" do
      tool = find_tool("get_memory_stats")
      stats = tool.execute.(%{})

      assert is_float(stats.total_mb)
      assert is_float(stats.processes_mb)
      assert is_float(stats.processes_used_mb)
      assert is_float(stats.system_mb)
      assert is_float(stats.binary_mb)
      assert is_float(stats.ets_mb)
      assert is_float(stats.code_mb)
    end
  end

  describe "get_process_stats tool" do
    test "returns expected structure" do
      tool = find_tool("get_process_stats")
      stats = tool.execute.(%{})

      assert is_integer(stats.process_count)
      assert is_integer(stats.process_limit)
      assert is_integer(stats.port_count)
      assert is_integer(stats.port_limit)
      assert stats.process_count > 0
      assert stats.process_limit > stats.process_count
    end
  end

  describe "get_scheduler_stats tool" do
    test "returns expected structure" do
      tool = find_tool("get_scheduler_stats")
      stats = tool.execute.(%{})

      assert is_integer(stats.schedulers)
      assert is_integer(stats.schedulers_online)
      assert is_integer(stats.dirty_cpu_schedulers_online)
      assert is_integer(stats.dirty_io_schedulers)
      assert is_integer(stats.run_queue)
      assert stats.schedulers >= stats.schedulers_online
    end
  end

  describe "get_atom_stats tool" do
    test "returns expected structure" do
      tool = find_tool("get_atom_stats")
      stats = tool.execute.(%{})

      assert is_integer(stats.atom_count)
      assert is_integer(stats.atom_limit)
      assert is_float(stats.atom_mb)
      assert is_float(stats.atom_used_mb)
      assert stats.atom_count > 0
      assert stats.atom_limit > stats.atom_count
    end
  end

  describe "get_persistent_terms tool" do
    test "returns expected structure" do
      tool = find_tool("get_persistent_terms")
      stats = tool.execute.(%{})

      assert is_integer(stats.count)
      assert is_float(stats.memory_mb)
      assert stats.count >= 0
    end
  end

  describe "get_top_processes tool" do
    test "returns expected structure with defaults" do
      tool = find_tool("get_top_processes")
      result = tool.execute.(%{})

      assert is_integer(result.total_processes)
      assert is_integer(result.showing)
      assert result.offset == 0
      assert result.limit == 10
      assert result.sort_by == "memory_kb"
      assert is_list(result.processes)
      assert result.showing <= 10
    end

    test "respects limit parameter" do
      tool = find_tool("get_top_processes")
      result = tool.execute.(%{limit: 5})

      assert result.limit == 5
      assert result.showing <= 5
    end

    test "respects offset parameter" do
      tool = find_tool("get_top_processes")
      result = tool.execute.(%{offset: 5})

      assert result.offset == 5
    end

    test "respects sort_by parameter" do
      tool = find_tool("get_top_processes")

      result = tool.execute.(%{sort_by: "reductions"})
      assert result.sort_by == "reductions"

      result = tool.execute.(%{sort_by: "message_queue"})
      assert result.sort_by == "message_queue"
    end

    test "caps limit at 50" do
      tool = find_tool("get_top_processes")
      result = tool.execute.(%{limit: 100})

      assert result.limit == 50
    end

    test "returns process info with expected fields" do
      tool = find_tool("get_top_processes")
      result = tool.execute.(%{limit: 1})

      if result.showing > 0 do
        [process | _] = result.processes

        assert is_binary(process.pid)
        assert is_integer(process.memory_kb)
        assert is_integer(process.message_queue)
        assert is_integer(process.reductions)
      end
    end
  end

  defp find_tool(intent) do
    Enum.find(Beam.tools(), fn tool -> tool.intent == intent end)
  end
end
