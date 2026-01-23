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

  alias Igniter.Code.Common
  alias Igniter.Code.Function
  alias Igniter.Code.Keyword
  alias Igniter.Code.List
  alias Igniter.Project.Module

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
    case patch_supervision_tree(igniter) do
      {:ok, igniter} -> igniter
      {:error, igniter} -> igniter
    end
  end

  defp patch_supervision_tree(igniter) do
    Module.find_and_update_module(igniter, Application, fn zipper ->
      case Function.move_to_function_call(zipper, :start, 2) do
        {:ok, zipper} ->
          add_beamlens_to_children(zipper)

        :error ->
          :error
      end
    end)
  end

  defp add_beamlens_to_children(zipper) do
    child_spec = build_child_spec()

    case Keyword.get_key(zipper, :children) do
      {:ok, zipper} ->
        case List.append_new_to_list(zipper, child_spec) do
          {:ok, zipper} ->
            {:ok, zipper}

          :error ->
            {:ok, Common.add_code(zipper, child_spec)}
        end

      :error ->
        {:ok, Common.add_code(zipper, child_spec)}
    end
  end

  defp build_child_spec do
    """
    # Beamlens monitors BEAM VM health using AI-driven operators.
    # Configure LLM providers with client_registry:
    #
    # {Beamlens, client_registry: %{
    #   primary: "Custom",
    #   clients: [
    #     %{name: "Custom", provider: "anthropic", options: %{model: "claude-3-5-haiku-latest"}}
    #   ]
    # }}
    #
    # See docs/providers.md for provider configuration options.
    {Beamlens, []}
    """
  end
end
