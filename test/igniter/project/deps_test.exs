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
end
