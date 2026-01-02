defmodule Beamlens.HealthReportTest do
  use ExUnit.Case

  alias Beamlens.HealthReport

  describe "schema/0" do
    test "parses valid BAML output with healthy status" do
      baml_output = %{
        status: "healthy",
        summary: "BEAM VM is operating normally",
        concerns: [],
        recommendations: []
      }

      assert {:ok, report} = Zoi.parse(HealthReport.schema(), baml_output)
      assert %HealthReport{} = report
      assert report.status == :healthy
      assert report.summary == "BEAM VM is operating normally"
      assert report.concerns == []
      assert report.recommendations == []
    end

    test "parses valid BAML output with warning status" do
      baml_output = %{
        status: "warning",
        summary: "High memory usage detected",
        concerns: ["Memory usage at 85%"],
        recommendations: ["Consider increasing memory allocation"]
      }

      assert {:ok, report} = Zoi.parse(HealthReport.schema(), baml_output)
      assert report.status == :warning
      assert report.concerns == ["Memory usage at 85%"]
    end

    test "parses valid BAML output with critical status" do
      baml_output = %{
        status: "critical",
        summary: "System is under heavy load",
        concerns: ["Run queue too high", "Memory exhaustion imminent"],
        recommendations: ["Scale horizontally", "Increase process limits"]
      }

      assert {:ok, report} = Zoi.parse(HealthReport.schema(), baml_output)
      assert report.status == :critical
      assert length(report.concerns) == 2
      assert length(report.recommendations) == 2
    end
  end
end
