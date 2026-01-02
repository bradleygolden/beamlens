defmodule Beamlens.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Beamlens.Runner, runner_opts()}
    ]

    opts = [strategy: :one_for_one, name: Beamlens.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp runner_opts do
    [
      mode: Application.get_env(:beamlens, :mode, :periodic),
      interval: Application.get_env(:beamlens, :interval, :timer.minutes(5))
    ]
  end
end
