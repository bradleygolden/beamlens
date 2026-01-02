defmodule Beamlens.HealthAnalysisTest do
  use ExUnit.Case

  alias Beamlens.HealthAnalysis

  describe "schema/0" do
    test "parses valid BAML output with healthy status" do
      baml_output = %{
        status: "healthy",
        summary: "BEAM VM is operating normally",
        concerns: [],
        recommendations: []
      }

      assert {:ok, analysis} = Zoi.parse(HealthAnalysis.schema(), baml_output)
      assert %HealthAnalysis{} = analysis
      assert analysis.status == :healthy
      assert analysis.summary == "BEAM VM is operating normally"
      assert analysis.concerns == []
      assert analysis.recommendations == []
    end

    test "parses valid BAML output with warning status" do
      baml_output = %{
        status: "warning",
        summary: "High memory usage detected",
        concerns: ["Memory usage at 85%"],
        recommendations: ["Consider increasing memory allocation"]
      }

      assert {:ok, analysis} = Zoi.parse(HealthAnalysis.schema(), baml_output)
      assert analysis.status == :warning
      assert analysis.concerns == ["Memory usage at 85%"]
    end

    test "parses valid BAML output with critical status" do
      baml_output = %{
        status: "critical",
        summary: "System is under heavy load",
        concerns: ["Run queue too high", "Memory exhaustion imminent"],
        recommendations: ["Scale horizontally", "Increase process limits"]
      }

      assert {:ok, analysis} = Zoi.parse(HealthAnalysis.schema(), baml_output)
      assert analysis.status == :critical
      assert length(analysis.concerns) == 2
      assert length(analysis.recommendations) == 2
    end
  end
end
