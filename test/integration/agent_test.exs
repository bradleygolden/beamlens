defmodule Beamlens.Integration.AgentTest do
  @moduledoc false

  use ExUnit.Case, async: false

  @moduletag :integration

  describe "Agent.run/1 with default provider" do
    @describetag timeout: 120_000

    test "runs agent loop and returns health analysis" do
      {:ok, analysis} = Beamlens.Agent.run(max_iterations: 10)

      assert %Beamlens.HealthAnalysis{} = analysis
      assert analysis.status in [:healthy, :warning, :critical]
      assert is_binary(analysis.summary)
      assert is_list(analysis.concerns)
      assert is_list(analysis.recommendations)
    end
  end
end
