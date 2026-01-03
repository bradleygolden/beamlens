defmodule Beamlens.AgentTest do
  @moduledoc false

  use ExUnit.Case, async: true

  describe "run/1 timeout option" do
    test "accepts timeout option" do
      # This will fail because there's no LLM available, but it should
      # accept the timeout option without raising
      result = Beamlens.Agent.run(timeout: 100)

      # Should return an error (no LLM configured), not a function clause error
      assert {:error, _reason} = result
    end

    test "uses default timeout when not specified" do
      # Verify the function works with default timeout
      result = Beamlens.Agent.run()

      # Should return an error (no LLM configured)
      assert {:error, _reason} = result
    end
  end
end
