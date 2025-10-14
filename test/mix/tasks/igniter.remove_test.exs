# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.Igniter.RemoveTest do
  use ExUnit.Case
  import Igniter.Test

  test "removes dependencies" do
    test_project()
    |> Igniter.Project.Deps.add_dep({:req, ">= 0.0.0"})
    |> apply_igniter!()
    |> Igniter.compose_task("igniter.remove", ["req"])
    |> assert_has_patch("mix.exs", """
     - |  {:req, ">= 0.0.0"}
    """)
    |> assert_has_task("deps.clean", ["--unlock", "--unused"])
  end
end
