defmodule Igniter.Libs.PhoenixTest do
  use ExUnit.Case
  import Igniter.Test

  describe "controller?/2" do
    test "detects a phoenix controller" do
      igniter =
        assert mix_project()
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
end
