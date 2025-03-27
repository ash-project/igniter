defmodule Mix.Tasks.Igniter.AddTest do
  use ExUnit.Case
  import Igniter.Test

  test "adds dependencies" do
    test_project()
    |> apply_igniter!()
    |> Igniter.compose_task("igniter.add", ["req"])
    |> assert_has_patch("mix.exs", """
     + |  {:req,
    """)
    |> assert_has_task("deps.get", [])
  end
end
