defmodule Igniter.Project.DepsTest do
  use ExUnit.Case

  import Igniter.Test

  describe "add_dep/3" do
    test "adds the provided dependency" do
      assert {:ok, nil} = Igniter.Project.Deps.get_dep(Igniter.new(), :foobar)

      igniter = Igniter.Project.Deps.add_dep(Igniter.new(), {:foobar, "~> 2.0"})

      assert Igniter.Project.Deps.get_dep(igniter, :foobar) ==
               {:ok, "{:foobar, \"~> 2.0\"}"}
    end

    test "adds the provided dependency in a tuple format" do
      test_project()
      |> Igniter.Project.Deps.add_dep({:foobar, "~> 2.0"})
      |> assert_has_patch("mix.exs", "+ | {:foobar, \"~> 2.0\"}")
      |> Igniter.Project.Deps.add_dep({:barfoo, "~> 1.0"})
      |> assert_has_patch("mix.exs", "+ | {:barfoo, \"~> 1.0\"}")
    end

    test "adds the provided dependency with options" do
      refute Igniter.Project.Deps.get_dependency_declaration(Igniter.new(), :foobar)

      igniter = Igniter.Project.Deps.add_dep(Igniter.new(), {:foobar, "~> 2.0", only: :test})

      assert Igniter.Project.Deps.get_dependency_declaration(igniter, :foobar) ==
               "{:foobar, \"~> 2.0\", only: :test}"
    end

    test "can be configured to add deps to a specific variable" do
      igniter =
        test_project(
          files: %{
            "mix.exs" => """
            defmodule Test.MixProject do
              use Mix.Project

              def project do
                [
                  app: :test,
                  version: "0.1.0",
                  elixir: "~> 1.17",
                  start_permanent: Mix.env() == :prod,
                  deps: deps()
                ]
              end

              # Run "mix help compile.app" to learn about applications.
              def application do
                [
                  extra_applications: [:logger]
                ]
              end

              # Run "mix help deps" to learn about dependencies.
              defp deps do
                deps = [] 

                if 1 == 2 do
                  deps
                else 
                  deps ++ [{:req, "~> 1.0"}]
                end
              end
            end
            """
          }
        )
        |> Igniter.Project.IgniterConfig.configure(
          :deps_location,
          {:variable, :deps}
        )

      igniter =
        igniter
        |> Igniter.Project.Deps.add_dep({:foobar, "~> 2.0"})
        |> assert_has_patch("mix.exs", """
        + |    deps = [{:foobar, "~> 2.0"}]
        """)

      refute :foobar in (igniter.assigns[:failed_to_add_deps] || [])
    end

    test "tracks when deps fail to be added" do
      igniter =
        test_project(
          files: %{
            "mix.exs" => """
            defmodule Test.MixProject do
              use Mix.Project

              def project do
                [
                  app: :test,
                  version: "0.1.0",
                  elixir: "~> 1.17",
                  start_permanent: Mix.env() == :prod,
                  deps: deps()
                ]
              end

              # Run "mix help compile.app" to learn about applications.
              def application do
                [
                  extra_applications: [:logger]
                ]
              end

              # Run "mix help deps" to learn about dependencies.
              defp deps do
                deps = [] 

                if 1 == 2 do
                  deps
                else 
                  deps ++ [{:req, "~> 1.0"}]
                end
              end
            end
            """
          }
        )

      igniter =
        Igniter.Project.Deps.add_dep(igniter, {:foobar, "~> 2.0", only: :test})

      assert :foobar in igniter.assigns[:failed_to_add_deps]
    end
  end

  describe "set_dep_option" do
    test "sets the option when no options exist" do
      test_project()
      |> Igniter.Project.Deps.add_dep({:foobar, "~> 2.0"})
      |> apply_igniter!()
      |> Igniter.Project.Deps.set_dep_option(:foobar, :only, :test)
      |> assert_has_patch("mix.exs", """
      - | {:foobar, "~> 2.0"}
      + | {:foobar, "~> 2.0", only: :test}
      """)
    end
  end
end
