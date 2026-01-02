defmodule Beamlens.Integration.AgentTest do
  @moduledoc false

  use ExUnit.Case, async: false

  @moduletag :integration

  setup do
    case check_ollama_available() do
      :ok ->
        :ok

      {:error, reason} ->
        flunk("Ollama is not available: #{reason}. Start Ollama with: ollama serve")
    end
  end

  describe "Agent.run/1 with Ollama" do
    @tag timeout: 120_000
    test "runs agent loop and returns health analysis" do
      {:ok, analysis} = Beamlens.Agent.run(llm_client: "Ollama", max_iterations: 10)

      assert %Beamlens.HealthAnalysis{} = analysis
      assert analysis.status in [:healthy, :warning, :critical]
      assert is_binary(analysis.summary)
      assert is_list(analysis.concerns)
      assert is_list(analysis.recommendations)
    end
  end

  defp check_ollama_available do
    Application.ensure_all_started(:inets)
    url = ~c"http://localhost:11434/api/tags"

    case :httpc.request(:get, {url, []}, [timeout: 5000], []) do
      {:ok, {{_, 200, _}, _, _}} ->
        :ok

      {:ok, {{_, status, _}, _, _}} ->
        {:error, "Ollama returned status #{status}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end
end
