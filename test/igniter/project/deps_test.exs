defmodule Igniter.Project.DepsTest do
  use ExUnit.Case

  import Igniter.Test

  describe "add_dep/3" do
    test "adds the provided dependency" do
      refute Igniter.Project.Deps.get_dependency_declaration(Igniter.new(), :foobar)

      igniter = Igniter.Project.Deps.add_dep(Igniter.new(), {:foobar, "~> 2.0"})

      assert Igniter.Project.Deps.get_dependency_declaration(igniter, :foobar) ==
               "{:foobar, \"~> 2.0\"}"
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
        assert spec |> to_string() |> Igniter.Project.Deps.determine_dep_type_and_version() ==
                 expected
      end
    end
  end
end
