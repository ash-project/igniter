defmodule Igniter.Project.IgniterConfigTest do
  use ExUnit.Case
  import Igniter.Test

  describe "add_extension/2" do
    test "adds an extension to the list" do
      mix_project()
      |> Igniter.Project.IgniterConfig.add_extension(Foobar)
      |> assert_has_patch(".igniter.exs", """
      9 - |  extensions: []
      9 + |  extensions: [{Foobar, []}]
      """)
    end
  end

  describe "dont_move_file_pattern/2" do
    test "adds a pattern to the list" do
      mix_project()
      |> Igniter.Project.IgniterConfig.dont_move_file_pattern(~r"abc")
      |> assert_has_patch(".igniter.exs", """
      8 - |  dont_move_files: [~r"lib/mix"],
      8 + |  dont_move_files: [~r/abc/, ~r"lib/mix"],
      """)
    end

    test "doesnt add a duplicate pattern to the list" do
      mix_project()
      |> Igniter.Project.IgniterConfig.dont_move_file_pattern(~r"lib/mix")
      |> assert_unchanged(".igniter.exs")
    end
  end
end
