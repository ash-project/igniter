defmodule IgniterTest do
  use ExUnit.Case
  doctest Igniter

  describe "Igniter.copy_template/4" do
    test "it evaluates and writes the template" do
      %{rewrite: rewrite} =
        Igniter.new()
        |> Igniter.copy_template("test/templates/template.css.eex", "lib/foobar.css",
          class: "hello"
        )

      config_file = Rewrite.source!(rewrite, "lib/foobar.css")

      assert Rewrite.Source.get(config_file, :content) == """
             .hello {
                background: black
             }
             """
    end
  end
end
