# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Igniter.Extensions.PhoenixTest do
  use ExUnit.Case
  import Igniter.Test

  describe "proper_location/2" do
    test "extensions are honored even if the extension is added in the same check" do
      test_project()
      |> Igniter.Project.IgniterConfig.add_extension(Igniter.Extensions.Phoenix)
      |> Igniter.Project.Module.create_module(TestWeb.FooController, """
        use TestWeb, :controller
      """)
      |> assert_creates("lib/test_web/controllers/foo_controller.ex")
    end

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

    test "when not belonging to a controller, we say we don't know where it goes" do
      igniter =
        test_project()
        |> Igniter.create_new_file("lib/test_web/controllers/foo_html.ex", """
        defmodule TestWeb.FooHTML do
          use TestWeb, :html
        end
        """)

      assert :error =
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

      assert Igniter.Extensions.Phoenix.proper_location(igniter, TestWeb.FooJSON, []) ==
               {:ok, "test_web/controllers/foo_json.ex"}
    end
  end

  describe "Live namespace handling" do
    test "does not duplicate 'live' directory for modules with Live namespace segment" do
      igniter =
        test_project()
        |> Igniter.Project.IgniterConfig.add_extension(Igniter.Extensions.Phoenix)

      module_name = MyApp.Live.Dashboard.TestLive

      igniter =
        Igniter.Project.Module.create_module(igniter, module_name, """
        @moduledoc "Test module"
        def hello, do: :world
        """)

      {:ok, {_igniter, source, _zipper}} =
        Igniter.Project.Module.find_module(igniter, module_name)

      actual_path = Rewrite.Source.get(source, :path)

      refute actual_path =~ ~r/live\/live/,
             "Module path should not contain duplicate 'live/live' directories. Got: #{actual_path}"

      assert actual_path == "lib/my_app/live/dashboard/test_live.ex"
    end

    test "correctly handles LiveView modules with Web prefix" do
      igniter =
        test_project()
        |> Igniter.Project.IgniterConfig.add_extension(Igniter.Extensions.Phoenix)

      module_name = TestWeb.DashboardLive

      igniter =
        Igniter.Project.Module.create_module(igniter, module_name, """
        use TestWeb, :live_view

        def render(assigns) do
          ~H"<div>Test</div>"
        end
        """)

      {:ok, {_igniter, source, _zipper}} =
        Igniter.Project.Module.find_module(igniter, module_name)

      actual_path = Rewrite.Source.get(source, :path)

      assert actual_path == "lib/test_web/live/dashboard_live.ex"
    end
  end
end
