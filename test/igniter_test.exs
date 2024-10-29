defmodule IgniterTest do
  use ExUnit.Case
  doctest Igniter

  import Igniter.Test

  describe "Igniter.copy_template/4" do
    test "it evaluates and writes the template" do
      mix_project()
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
      mix_project()
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
end
