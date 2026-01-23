defmodule Mix.Tasks.Beamlens.Install do
  @shortdoc "Sets up Beamlens in your project."
  @moduledoc """
  #{@shortdoc}

  Running this command will automatically create the Beamlens configuration file
  and add Beamlens to your supervision tree.

  ## Example

      $ mix igniter.install beamlens

  This will:
  - Add beamlens to mix.exs dependencies
  - Create config/beamlens.exs with LLM provider configuration
  - Add Beamlens to your Application's supervision tree
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
    igniter
    |> create_config_file()
    |> patch_supervision_tree()
  end

  defp create_config_file(igniter) do
    config_content = """
    import Config

    # Beamlens uses Anthropic (claude-haiku-4-5-20251001) by default.
    # Set your ANTHROPIC_API_KEY environment variable and you're ready to go.
    #
    # Beamlens has been added to your Application's supervision tree.
    # To customize skills or LLM providers, see your Application module
    # or refer to docs/providers.md for configuration examples.
    """

    Igniter.create_new_file(igniter, "config/beamlens.exs", config_content)
  end

  defp patch_supervision_tree(igniter) do
    Module.find_and_update_module!(igniter, "Application", fn zipper ->
      case Function.move_to_function_call(zipper, :start, 2) do
        {:ok, zipper} ->
          add_beamlens_to_children(zipper)

        :error ->
          {:warning, supervision_tree_fallback()}
      end
    end)
  end

  defp add_beamlens_to_children(zipper) do
    child_spec = build_child_spec()

    with {:ok, zipper} <- Keyword.get_key(zipper, :children),
         {:ok, zipper} <- List.append_new_to_list(zipper, child_spec) do
      {:ok, zipper}
    else
      _ ->
        # If we can't append to the list, try adding it to the function body
        Common.add_code(zipper, child_spec)
    end
  end

  defp build_child_spec do
    """
            {Beamlens, []}
    """
  end

  defp supervision_tree_fallback do
    """

    Could not automatically add Beamlens to your supervision tree.
    Please add it manually to your Application module's children list:

        children = [
          {Beamlens, []}
        ]
    """
  end
end
