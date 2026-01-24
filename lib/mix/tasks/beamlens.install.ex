defmodule Mix.Tasks.Beamlens.Install do
  @shortdoc "Sets up Beamlens in your project."
  @moduledoc """
  #{@shortdoc}

  Running this command will add Beamlens to your supervision tree.

  ## Example

      $ mix igniter.install beamlens

  This will:
  - Add beamlens to mix.exs dependencies
  - Add Beamlens to your Application's supervision tree

  Beamlens uses default skills and Anthropic claude-haiku. Set the ANTHROPIC_API_KEY
  environment variable to get started. Refer to docs/providers.md for customization.
  """

  use Igniter.Mix.Task

  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      adds_deps: [{:beamlens, nil}],
      installs: [],
      composes: [],
      positional: [],
      schema: [],
      defaults: [],
      aliases: [],
      example: "mix igniter.install beamlens"
    }
  end

  @doc false
  @impl true
  def igniter(igniter) do
    # Use Igniter's built-in function to add a child to the supervision tree
    Igniter.Project.Application.add_new_child(igniter, {Beamlens, []})
  end
end
