defmodule Beamlens.AgentTest do
  use ExUnit.Case, async: true

  alias Beamlens.Agent

  describe "investigate/2" do
    test "returns {:ok, :no_alerts} with empty list" do
      assert {:ok, :no_alerts} = Agent.investigate([])
    end

    test "returns {:ok, :no_alerts} with empty list and options" do
      assert {:ok, :no_alerts} = Agent.investigate([], timeout: 5000)
    end
  end
end
