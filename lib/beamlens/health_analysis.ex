defmodule Beamlens.HealthAnalysis do
  @moduledoc """
  Structured health analysis from BeamLens agent.
  """

  @type status :: :healthy | :warning | :critical

  @type t :: %__MODULE__{
          status: status(),
          summary: String.t(),
          concerns: [String.t()],
          recommendations: [String.t()]
        }

  @derive Jason.Encoder
  defstruct [:status, :summary, concerns: [], recommendations: []]

  @doc """
  Returns the ZOI schema for parsing BAML output into this struct.
  """
  def schema do
    Zoi.object(%{
      status: Zoi.string() |> Zoi.transform(&parse_status/1),
      summary: Zoi.string(),
      concerns: Zoi.array(Zoi.string()),
      recommendations: Zoi.array(Zoi.string())
    })
    |> Zoi.transform(&to_struct/1)
  end

  defp parse_status("healthy"), do: {:ok, :healthy}
  defp parse_status("warning"), do: {:ok, :warning}
  defp parse_status("critical"), do: {:ok, :critical}

  defp to_struct(map), do: {:ok, struct(__MODULE__, map)}
end
