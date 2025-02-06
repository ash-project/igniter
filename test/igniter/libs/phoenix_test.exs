defmodule Igniter.Libs.PhoenixTest do
  use ExUnit.Case
  import Igniter.Test

  describe "controller?/2" do
    test "detects a phoenix controller" do
      igniter =
        assert test_project()
               |> Igniter.create_new_file("lib/test_web/controllers/foo_controller.ex", """
               defmodule TestWeb.FooController do
                 use TestWeb, :controller

               end
               """)
               |> Igniter.create_new_file("lib/test_web/controllers/foo_view.ex", """
               defmodule TestWeb.ThingView do
                 use TestWeb, :view

               end
               """)
               |> apply_igniter!()

      assert Igniter.Libs.Phoenix.controller?(igniter, TestWeb.FooController)
      refute Igniter.Libs.Phoenix.controller?(igniter, TestWeb.ThingView)
    end
  end

  describe "web_module/1" do
    test "append Web" do
      mix_exs = """
      defmodule Test.MixProject do
      end
      """

      igniter =
        assert test_project()
               |> Igniter.create_or_update_elixir_file(
                 "mix.exs",
                 mix_exs,
                 &{:ok, Igniter.Code.Common.replace_code(&1, mix_exs)}
               )
               |> apply_igniter!()

      assert Igniter.Libs.Phoenix.web_module(igniter) == TestWeb
    end

    test "do not append Web suffix if name already ends with Web" do
      mix_exs = """
      defmodule TestWeb.MixProject do
      end
      """

      igniter =
        assert test_project()
               |> Igniter.create_or_update_elixir_file(
                 "mix.exs",
                 mix_exs,
                 &{:ok, Igniter.Code.Common.replace_code(&1, mix_exs)}
               )
               |> apply_igniter!()

      assert Igniter.Libs.Phoenix.web_module(igniter) == TestWeb
    end
  end

  test "web_module_name/1" do
    assert Igniter.Libs.Phoenix.web_module_name(test_project(), "Suffix") == TestWeb.Suffix
  end
end
