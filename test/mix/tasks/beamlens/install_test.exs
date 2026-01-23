defmodule Mix.Tasks.Beamlens.InstallTest do
  use ExUnit.Case
  import Igniter.Test

  alias Igniter.Project.Module
  alias Mix.Tasks.Beamlens.Install

  describe "igniter/1" do
    test "adds Beamlens to supervision tree when Application module exists" do
      project =
        test_project()
        |> Module.create_module(Application, """
        defmodule Application do
          use Application

          def start(_type, _args) do
            children = [
              {OtherChild, []}
            ]

            opts = [strategy: :one_for_one, name: MyApp.Supervisor]
            Supervisor.start_link(children, opts)
          end
        end
        """)
        |> Install.igniter()

      # Apply igniter and verify it succeeds
      assert %Igniter{} = apply_igniter!(project)
    end

    test "adds Beamlens child spec to existing children list" do
      project =
        test_project()
        |> Module.create_module(Application, """
        defmodule Application do
          use Application

          def start(_type, _args) do
            children = [
              {OtherChild, []}
            ]

            opts = [strategy: :one_for_one, name: MyApp.Supervisor]
            Supervisor.start_link(children, opts)
          end
        end
        """)
        |> Install.igniter()
        |> apply_igniter!()

      # Verify the modified module contains Beamlens child spec and configuration comment
      modified_source =
        Rewrite.source!(project.rewrite, "lib/application.ex") |> Rewrite.Source.get(:content)

      # Visual assertion: Beamlens child spec should be present
      assert modified_source =~ "{Beamlens, []}"

      # Visual assertion: Configuration comment should be present
      assert modified_source =~ "# Configure LLM providers with client_registry:"
    end

    test "creates children list when none exists" do
      project =
        test_project()
        |> Module.create_module(Application, """
        defmodule Application do
          use Application

          def start(_type, _args) do
            opts = [strategy: :one_for_one, name: MyApp.Supervisor]
            Supervisor.start_link([], opts)
          end
        end
        """)
        |> Install.igniter()
        |> apply_igniter!()

      # Verify the modified module contains Beamlens child spec and configuration comment
      modified_source =
        Rewrite.source!(project.rewrite, "lib/application.ex") |> Rewrite.Source.get(:content)

      # Visual assertion: Beamlens child spec should be present
      assert modified_source =~ "{Beamlens, []}"

      # Visual assertion: Configuration comment should be present
      assert modified_source =~ "# Configure LLM providers with client_registry:"
    end

    test "does not create config file" do
      project =
        test_project()
        |> Module.create_module(Application, """
        defmodule Application do
          use Application

          def start(_type, _args) do
            children = []

            opts = [strategy: :one_for_one, name: MyApp.Supervisor]
            Supervisor.start_link(children, opts)
          end
        end
        """)
        |> Install.igniter()
        |> apply_igniter!()

      refute_creates(project, "config/beamlens.exs")
    end

    test "handles missing Application module gracefully" do
      igniter =
        test_project()
        |> Install.igniter()

      assert %Igniter{} = igniter
    end
  end
end
