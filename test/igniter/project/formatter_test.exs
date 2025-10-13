# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule Igniter.Project.FormatterTest do
  use ExUnit.Case
  import Igniter.Test

  describe "import_dep/2" do
    test "regression: causes formatting to respect imported locals_without_parens" do
      test_project(
        files: %{
          "test/formatter_test.exs" => """
          defmodule FormatterTest do
            use ExUnit.Case
            use Mimic.DSL

            test "1" do
              expect Foo.add(x, y), do: x + y
            end
          end
          """
        }
      )
      |> Igniter.Project.Deps.add_dep({:mimic, "~> 1.7"})
      |> Igniter.Project.Formatter.import_dep(:mimic)
      |> Igniter.update_elixir_file("test/formatter_test.exs", fn zipper ->
        with {:ok, zipper} <- Igniter.Code.Module.move_to_defmodule(zipper),
             {:ok, zipper} <- Igniter.Code.Common.move_to_do_block(zipper),
             zipper <- Igniter.Code.Common.maybe_move_to_block(zipper) do
          zipper =
            zipper
            |> Sourceror.Zipper.rightmost()
            |> Igniter.Code.Common.add_code("""
            test "2" do
              expect Foo.subtract(x, y), do: x - y
            end
            """)

          {:ok, zipper}
        end
      end)
      |> assert_has_patch("test/formatter_test.exs", """
        |  end
      + |
      + |  test "2" do
      + |    expect Foo.subtract(x, y), 
      + |      do: x - y
      + |  end
        |end
      """)
    end
  end
end
