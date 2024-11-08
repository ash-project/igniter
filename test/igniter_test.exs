defmodule IgniterTest do
  use ExUnit.Case
  doctest Igniter

  import Igniter.Test

  describe "Igniter.copy_template/4" do
    test "it evaluates and writes the template" do
      test_project()
      |> Igniter.copy_template("test/templates/template.css.eex", "lib/foobar.css",
        class: "hello"
      )
      |> assert_creates("lib/foobar.css", """
      .hello {
         background: black
      }
      """)
    end

    test "it overwrites an existing file" do
      test_project()
      |> Igniter.copy_template("test/templates/template.css.eex", "lib/foobar.css",
        class: "hello"
      )
      |> apply_igniter!()
      |> Igniter.copy_template(
        "test/templates/template.css.eex",
        "lib/foobar.css",
        [class: "goodbye"],
        on_exists: :overwrite
      )
      |> assert_has_patch("lib/foobar.css", """
      1 - |.hello {
      1 + |.goodbye {
      """)
    end
  end

  describe "diff formatting" do
    test "contains uniform blank lines between diifs" do
      diff =
        test_project()
        |> Igniter.update_elixir_file("mix.exs", fn zipper ->
          {:ok, Igniter.Code.Common.add_code(zipper, ":ok")}
        end)
        |> Igniter.update_elixir_file("lib/test.ex", fn zipper ->
          {:ok, Igniter.Code.Common.add_code(zipper, ":ok")}
        end)
        |> Igniter.create_new_file("lib/test/example.ex", ":ok\n")
        |> Igniter.create_new_file("lib/test/example2.ex", ":ok\n")
        |> diff()

      assert diff == """

             Update: lib/test.ex

                  ...|
             18 18   |end
             19 19   |
                20 + |:ok
                21 + |


             Create: lib/test/example.ex

             1 |:ok
             2 |


             Create: lib/test/example2.ex

             1 |:ok
             2 |


             Update: mix.exs

                  ...|
             28 28   |end
             29 29   |
                30 + |:ok
                31 + |

             """
    end
  end
end
