defmodule Beamlens.Collector do
  @moduledoc """
  Behaviour for implementing collectors.

  Collectors provide tools that the LLM agent can invoke to gather
  information. Each collector returns a list of `Beamlens.Tool` structs.

  ## Example

      defmodule MyApp.Collectors.Postgres do
        @behaviour Beamlens.Collector

        alias Beamlens.Tool

        @impl true
        def tools do
          [
            %Tool{
              name: :pool_stats,
              intent: "get_postgres_pool_stats",
              description: "Get connection pool statistics",
              execute: &pool_stats/0
            }
          ]
        end

        defp pool_stats do
          %{size: 10, available: 7}
        end
      end
  """

  @doc """
  Returns list of tools this collector provides.
  """
  @callback tools() :: [Beamlens.Tool.t()]
end
