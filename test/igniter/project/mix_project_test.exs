# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule Igniter.Project.MixProjectTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  alias Igniter.Project.MixProject
  alias Sourceror.Zipper

  describe "update/4 inline keyword option" do
    test "updates with a zipper" do
      test_project()
      |> MixProject.update(:project, [:version], fn zipper ->
        {:ok, Zipper.replace(zipper, "CHANGED")}
      end)
      |> assert_has_patch("mix.exs", """
        |      app: :test,
      - |      version: "0.1.0",
      + |      version: "CHANGED",
        |      elixir: "~> 1.17",
      """)
    end

    test "doesn't strip lists when setting compilers" do
      test_project()
      |> Igniter.Project.MixProject.update(:project, [:compilers], fn
        nil ->
          {:ok,
           {:code,
            quote do
              [:phoenix_live_view] ++ Mix.compilers()
            end}}

        _zipper ->
          raise "nope"
      end)
      |> assert_has_patch("mix.exs", """
      + | compilers: [:phoenix_live_view] ++ Mix.compilers()
      """)
    end

    test "updates with a code tuple" do
      test_project()
      |> MixProject.update(:project, [:version], fn _zipper ->
        {:ok, {:code, {:__block__, [], ["CHANGED"]}}}
      end)
      |> assert_has_patch("mix.exs", """
        |      app: :test,
      - |      version: "0.1.0",
      + |      version: "CHANGED",
        |      elixir: "~> 1.17",
      """)
    end

    test "is removed with nil" do
      test_project()
      |> MixProject.update(:project, [:version], fn _ ->
        {:ok, nil}
      end)
      |> assert_has_patch("mix.exs", """
        |      app: :test,
      - |      version: "0.1.0",
        |      elixir: "~> 1.17",
      """)
    end

    test "is created with returned code" do
      test_project()
      |> MixProject.update(:project, [:aliases, :foo], fn nil ->
        {:ok, {:code, :bar}}
      end)
      |> assert_has_patch("mix.exs", """
      - |      deps: deps()
      + |      deps: deps(),
      + |      aliases: [foo: :bar]
      """)
    end
  end

  describe "update/4 keyword options with private function" do
    setup do
      [
        project:
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
                    deps: deps(),
                    aliases: aliases(Mix.env())
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
                  [
                    # {:dep_from_hexpm, "~> 0.3.0"},
                    # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
                  ]
                end

                defp aliases(env) do
                  # to test that config can be found when it's not the only
                  # thing in the function body
                  env = env

                  [
                    foo_alias: :foo
                  ]
                end
              end
              """
            }
          )
      ]
    end

    test "resolves the option value to a local function containing a list", %{project: project} do
      project
      |> MixProject.update(:project, [:deps], fn zipper ->
        # should be the list inside deps/0
        assert Igniter.Code.List.list?(zipper)

        Igniter.Code.List.append_to_list(
          zipper,
          Sourceror.parse_string!("{:test_dep, \"0.1.0\"}")
        )
      end)
      |> assert_has_patch("mix.exs", """
         |    [
       + |      {:test_dep, "0.1.0"}
         |      # {:dep_from_hexpm, "~> 0.3.0"}
      """)
    end

    test "resolves the option value to a local function ending with a list", %{project: project} do
      project
      |> MixProject.update(:project, [:aliases, :bar_alias], fn nil ->
        {:ok, {:code, :bar}}
      end)
      |> assert_has_patch("mix.exs", """
         |    [
       - |      foo_alias: :foo
       + |      foo_alias: :foo,
       + |      bar_alias: :bar
         |    ]
      """)
    end
  end

  describe "update/4 keyword options with module attributes" do
    setup do
      [
        project:
          test_project(
            files: %{
              "mix.exs" => """
              defmodule Test.MixProject do
                use Mix.Project

                @version "0.1.0"

                def project do
                  [
                    app: :test,
                    version: @version,
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
                  [
                    # {:dep_from_hexpm, "~> 0.3.0"},
                    # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
                  ]
                end
              end
              """
            }
          )
      ]
    end

    test "updates the module attribute definition with a code tuple", %{project: project} do
      project
      |> MixProject.update(:project, [:version], fn zipper ->
        {:ok, Zipper.replace(zipper, "CHANGED")}
      end)
      |> assert_has_patch("mix.exs", """
      - |  @version "0.1.0"
      + |  @version "CHANGED"
      """)
    end
  end

  describe "update/4 with non-existing function" do
    test "creates the function" do
      test_project()
      |> MixProject.update(:cli, [:preferred_envs, :"some.task"], fn _ ->
        {:ok, {:code, :test}}
      end)
      |> assert_has_patch("mix.exs", """
        |  end
        |
      + |  def cli do
      + |    [
      + |      preferred_envs: ["some.task": :test]
      + |    ]
      + |  end
      + |
        |  # Run "mix help deps" to learn about dependencies.
        |  defp deps do
      """)
    end
  end
end
