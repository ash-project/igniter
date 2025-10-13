# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule Igniter.Project.TaskAliasesTest do
  use ExUnit.Case
  import Igniter.Test

  describe "add_alias/3-4" do
    test "adds a task alias to the `mix.exs` file" do
      test_project()
      |> Igniter.Project.TaskAliases.add_alias("test", "test --special")
      |> assert_has_patch("mix.exs", """
      10 + | deps: deps(),
      11 + | aliases: aliases()
      """)
      |> assert_has_patch("mix.exs", """
      30 + |  defp aliases() do
      31 + |    [test: "test --special"]
      32 + |  end
      """)
    end

    test "by default, it ignores existing aliases" do
      test_project()
      |> Igniter.Project.TaskAliases.add_alias("test", "test --special")
      |> apply_igniter!()
      |> Igniter.Project.TaskAliases.add_alias("test", "my_thing.setup_tests")
      |> assert_unchanged()
    end

    test "the alter option can be used to modify existing aliases" do
      test_project()
      |> Igniter.Project.TaskAliases.add_alias("test", "test --special")
      |> apply_igniter!()
      |> Igniter.Project.TaskAliases.add_alias("test", "my_thing.setup_tests",
        if_exists: :prepend
      )
      |> assert_has_patch("mix.exs", """
      31 - | [test: "test --special"]
      31 + | [test: ["my_thing.setup_tests", "test --special"]]
      """)
    end

    test "the alter option won't add steps that are already present" do
      test_project()
      |> Igniter.Project.TaskAliases.add_alias("test", ["my_thing.setup_tests", "test --special"])
      |> apply_igniter!()
      |> Igniter.Project.TaskAliases.add_alias("test", "my_thing.setup_tests",
        if_exists: :prepend
      )
      |> assert_unchanged()
    end
  end
end
