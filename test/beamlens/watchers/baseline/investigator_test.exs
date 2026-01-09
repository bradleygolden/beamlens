defmodule Beamlens.Watchers.Baseline.InvestigatorTest do
  use ExUnit.Case, async: true

  alias Beamlens.Alert
  alias Beamlens.Watchers.Baseline.Investigator

  describe "investigate/3" do
    test "returns {:error, :max_iterations_exceeded} when max_iterations is 0" do
      alert = build_test_alert()
      tools = []

      result = Investigator.investigate(alert, tools, max_iterations: 0)

      assert result == {:error, :max_iterations_exceeded}
    end
  end

  defp build_test_alert do
    Alert.new(%{
      watcher: :beam,
      anomaly_type: :test_anomaly,
      severity: :warning,
      summary: "Test anomaly for unit testing",
      snapshot: %{test: true}
    })
  end
end
