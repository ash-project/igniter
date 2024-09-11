defmodule Igniter.Extensions.PhoenixTest do
  use ExUnit.Case
  import Igniter.Test

  describe "proper_location/2" do
    test "returns a controller location" do
      igniter =
        test_project()
        |> Igniter.create_new_file("lib/test_web/controllers/foo_controller.ex", """
        defmodule TestWeb.FooController do
          use TestWeb, :controller

        end
        """)

      assert {:ok, "test_web/controllers/foo_controller.ex"} =
               Igniter.Extensions.Phoenix.proper_location(igniter, TestWeb.FooController, [])
    end

    test "when belonging to a controller, it returns an html location" do
      igniter =
        test_project()
        |> Igniter.create_new_file("lib/test_web/controllers/foo_controller.ex", """
        defmodule TestWeb.FooController do
          use TestWeb, :controller

        end
        """)
        |> Igniter.create_new_file("lib/test_web/controllers/foo_html.ex", """
        defmodule TestWeb.FooHTML do
          use TestWeb, :html
        end
        """)

      assert {:ok, "test_web/controllers/foo_html.ex"} =
               Igniter.Extensions.Phoenix.proper_location(igniter, TestWeb.FooHTML, [])
    end

    test "when not belonging to a controller, we instruct to keep its current location" do
      igniter =
        test_project()
        |> Igniter.create_new_file("lib/test_web/controllers/foo_html.ex", """
        defmodule TestWeb.FooHTML do
          use TestWeb, :html
        end
        """)

      assert :keep =
               Igniter.Extensions.Phoenix.proper_location(igniter, TestWeb.FooHTML, [])
    end

    test "returns a json location" do
      igniter =
        test_project()
        |> Igniter.create_new_file("test_web/controllers/foo_controller.ex", """
        defmodule TestWeb.FooController do
          use TestWeb, :controller

        end
        """)
        |> Igniter.create_new_file("lib/test_web/controllers/foo_json.ex", """
        defmodule TestWeb.FooJSON do

          def render(_), do: %{foo: "bar"}
        end
        """)

      assert {:ok, "test_web/controllers/foo_json.ex"} =
               Igniter.Extensions.Phoenix.proper_location(igniter, TestWeb.FooJSON, [])
    end
  end
end
