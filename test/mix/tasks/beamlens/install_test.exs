defmodule Mix.Tasks.Beamlens.InstallTest do
  use ExUnit.Case
  import Igniter.Test

  alias Igniter.Project.Module
  alias Mix.Tasks.Beamlens.Install

  describe "igniter/1" do
    test "adds Beamlens to supervision tree when Application module exists" do
      igniter =
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

      assert %Igniter{} = igniter
    end

    test "does not create config file" do
      igniter =
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

      refute_creates(igniter, "config/beamlens.exs")
    end

    test "handles missing Application module gracefully" do
      igniter =
        test_project()
        |> Install.igniter()

      assert %Igniter{} = igniter
    end
  end
end
