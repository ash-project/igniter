defmodule Igniter.Project.IgniterConfigTest do
  use ExUnit.Case
  import Igniter.Test

  describe "add_extension/2" do
    test "adds an extension to the list" do
      test_project()
      |> Igniter.Project.IgniterConfig.add_extension(Foobar)
      |> assert_has_patch(".igniter.exs", """
      12 12   |    ~r"lib/mix"
      13 13   |  ],
      14    - |  extensions: []
          14 + |  extensions: [{Foobar, []}]
      15 15   |]
      16 16   |
      """)
    end
  end

  describe "dont_move_file_pattern/2" do
    test "adds a pattern to the list" do
      test_project()
      |> Igniter.Project.IgniterConfig.dont_move_file_pattern(~r"abc")
      |> assert_has_patch(".igniter.exs", """
      11 11   |  dont_move_files: [
         12 + |    ~r/abc/,
      12 13   |    ~r"lib/mix"
      13 14   |  ],
      """)
    end

    test "doesnt add a duplicate pattern to the list" do
      test_project()
      |> Igniter.Project.IgniterConfig.dont_move_file_pattern(~r"lib/mix")
      |> assert_unchanged(".igniter.exs")
    end
  end
end
