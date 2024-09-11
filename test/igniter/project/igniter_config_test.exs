defmodule Igniter.Project.IgniterConfigTest do
  use ExUnit.Case
  import Igniter.Test

  describe "add_extension/2" do
    test "adds an extension to the list" do
      test_project()
      |> Igniter.Project.IgniterConfig.add_extension(Foobar)
      |> assert_has_patch(".igniter.exs", """
      11 11   |  dont_move_files: [
      12 12   |    ~r"lib/mix"
      13    - |  ]
        13 + |  ],
        14 + |  extensions: [{Foobar, []}]
      """)
    end
  end
end
