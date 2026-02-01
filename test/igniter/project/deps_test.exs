# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs/contributors>
#
# SPDX-License-Identifier: MIT

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
      assert {:ok, nil} = Igniter.Project.Deps.get_dep(Igniter.new(), :foobar)

      igniter = Igniter.Project.Deps.add_dep(Igniter.new(), {:foobar, "~> 2.0", only: :test})

      assert {:ok, "{:foobar, \"~> 2.0\", only: :test}"} =
               Igniter.Project.Deps.get_dep(igniter, :foobar)
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

  describe "get_dep/2" do
    test "detects existing dependencies when using deps_location variable" do
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
                shared_deps = [
                  {:ash_authentication, "~> 4.0"},
                  {:picosat_elixir, "~> 0.2"},
                  {:ash, "~> 3.5"}
                ]

                shared_deps
              end
            end
            """
          }
        )
        |> Igniter.Project.IgniterConfig.configure(
          :deps_location,
          {:variable, :shared_deps}
        )

      # Should detect existing dependency
      assert {:ok, "{:ash_authentication, \"~> 4.0\"}"} =
               Igniter.Project.Deps.get_dep(igniter, :ash_authentication)

      assert {:ok, "{:ash, \"~> 3.5\"}"} =
               Igniter.Project.Deps.get_dep(igniter, :ash)

      # Should return nil for non-existing dependency
      assert {:ok, nil} =
               Igniter.Project.Deps.get_dep(igniter, :non_existing_dep)
    end

    test "prevents duplicate dependencies when using deps_location variable" do
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
                shared_deps = [
                  {:ash_authentication, "~> 4.0"},
                  {:picosat_elixir, "~> 0.2"},
                  {:ash, "~> 3.5"}
                ]

                shared_deps
              end
            end
            """
          }
        )
        |> Igniter.Project.IgniterConfig.configure(
          :deps_location,
          {:variable, :shared_deps}
        )

      # Try to add an existing dependency - should not create duplicate
      igniter = Igniter.Project.Deps.add_dep(igniter, {:ash_authentication, "~> 4.0"})

      # Should still detect the existing dependency correctly
      assert {:ok, "{:ash_authentication, \"~> 4.0\"}"} =
               Igniter.Project.Deps.get_dep(igniter, :ash_authentication)

      # Should not have failed to add the dependency (no duplicates created)
      refute :ash_authentication in (igniter.assigns[:failed_to_add_deps] || [])
    end
  end

  describe "determine_dep_type_and_version/1" do
    test "parses to a version" do
      tests = [
        "dep@1.0.0": {:dep, "== 1.0.0"},
        "dep@1.0": {:dep, "~> 1.0"},
        "dep@git:git_url": {:dep, git: "git_url", override: true},
        "dep@git:git_url@ref": {:dep, git: "git_url", ref: "ref", override: true},
        "dep@github:user/repo": {:dep, github: "user/repo", override: true},
        "dep@github:user/repo@ref": {:dep, github: "user/repo", ref: "ref", override: true},
        "dep@path:path/to/dep": {:dep, path: "path/to/dep", override: true},
        "org/dep@1.0.0": {:dep, "== 1.0.0", organization: "org"},
        "org/dep@1.0": {:dep, "~> 1.0", organization: "org"},
        "org/dep@git:git_url": {:dep, git: "git_url", override: true, organization: "org"},
        "org/dep@git:git_url@ref":
          {:dep, git: "git_url", ref: "ref", override: true, organization: "org"},
        "org/dep@github:user/repo":
          {:dep, github: "user/repo", override: true, organization: "org"},
        "org/dep@github:user/repo@ref":
          {:dep, github: "user/repo", ref: "ref", override: true, organization: "org"},
        "org/dep@github:user/repo@branch@name":
          {:dep, github: "user/repo", ref: "branch@name", override: true, organization: "org"},
        "org/dep@github:user/repo@branch/name":
          {:dep, github: "user/repo", ref: "branch/name", override: true, organization: "org"},
        "org/dep@path:path/to/dep":
          {:dep, path: "path/to/dep", override: true, organization: "org"}
      ]

      for {spec, expected} <- tests do
        assert spec |> to_string() |> Igniter.Project.Deps.determine_dep_type_and_version!() ==
                 expected
      end
    end
  end
end
