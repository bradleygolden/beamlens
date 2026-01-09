defmodule Beamlens.CollectorTest do
  use ExUnit.Case, async: true

  describe "Collector behaviour" do
    test "defines tools/0 callback" do
      callbacks = Beamlens.Collector.behaviour_info(:callbacks)

      assert {:tools, 0} in callbacks
    end
  end

  describe "implementing the behaviour" do
    defmodule TestCollector do
      @behaviour Beamlens.Collector

      @impl true
      def tools do
        [
          %Beamlens.Tool{
            name: :test,
            intent: "test",
            description: "Test tool",
            execute: fn _params -> %{} end
          }
        ]
      end
    end

    test "implementation returns list of Tool structs" do
      tools = TestCollector.tools()

      assert is_list(tools)
      assert length(tools) == 1
      assert match?(%Beamlens.Tool{}, hd(tools))
    end
  end
end
