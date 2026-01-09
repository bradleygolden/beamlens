defmodule Beamlens.ToolTest do
  use ExUnit.Case, async: true

  alias Beamlens.Tool

  describe "Tool struct" do
    test "creates struct with all required keys" do
      tool = %Tool{
        name: :test_tool,
        intent: "get_test_data",
        description: "A test tool",
        execute: fn _params -> %{data: "test"} end
      }

      assert tool.name == :test_tool
      assert tool.intent == "get_test_data"
      assert tool.description == "A test tool"
      assert is_function(tool.execute, 1)
    end

    test "enforces required keys" do
      assert_raise ArgumentError, fn ->
        struct!(Tool, [])
      end

      assert_raise ArgumentError, fn ->
        struct!(Tool, name: :test)
      end

      assert_raise ArgumentError, fn ->
        struct!(Tool, name: :test, intent: "test")
      end
    end

    test "execute function receives params and returns result" do
      tool = %Tool{
        name: :echo,
        intent: "echo",
        description: "Echoes params",
        execute: fn params -> params end
      }

      assert tool.execute.(%{foo: "bar"}) == %{foo: "bar"}
    end
  end
end
