# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs.contributors>
#
# SPDX-License-Identifier: MIT

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

  describe "list_web_modules/1" do
    test "finds web modules that are one level deep and end with Web" do
      igniter =
        assert test_project()
               |> Igniter.create_new_file("lib/test_web.ex", """
               defmodule TestWeb do
                 use Phoenix.Web
               end
               """)
               |> Igniter.create_new_file("lib/admin_web.ex", """
               defmodule AdminWeb do
                 use Phoenix.Web
               end
               """)
               |> Igniter.create_new_file("lib/foo/bar_web.ex", """
               defmodule Foo.BarWeb do
                 use Phoenix.Web
               end
               """)
               |> Igniter.create_new_file("lib/user_web.ex", """
               defmodule UserWeb do
                 # This should match - one level deep, ends with Web
               end
               """)
               |> Igniter.create_new_file("lib/not_web_module.ex", """
               defmodule NotWebModule do
                 # This shouldn't match - doesn't end with Web
               end
               """)
               |> Igniter.create_new_file("lib/test_controller.ex", """
               defmodule TestController do
                 # This shouldn't match even though it's one level deep
               end
               """)
               |> apply_igniter!()

      {_igniter, web_modules} = Igniter.Libs.Phoenix.list_web_modules(igniter)

      # Should include modules that are one level deep and end with Web
      assert TestWeb in web_modules
      assert AdminWeb in web_modules
      assert UserWeb in web_modules

      # Should exclude modules that are two levels deep
      refute Foo.BarWeb in web_modules

      # Should exclude modules that don't end with Web
      refute NotWebModule in web_modules
      refute TestController in web_modules

      # Verify exact count
      assert length(web_modules) == 3
    end

    test "returns empty list when no web modules found" do
      igniter =
        assert test_project()
               |> Igniter.create_new_file("lib/foo.ex", """
               defmodule Foo do
                 # Not a web module
               end
               """)
               |> apply_igniter!()

      {_igniter, web_modules} = Igniter.Libs.Phoenix.list_web_modules(igniter)
      assert web_modules == []
    end
  end

  describe "web_module?/1" do
    test "returns true for valid web modules (atoms)" do
      assert Igniter.Libs.Phoenix.web_module?(TestWeb)
      assert Igniter.Libs.Phoenix.web_module?(AdminWeb)
      assert Igniter.Libs.Phoenix.web_module?(MyAppWeb)
    end

    test "returns true for valid web modules (strings)" do
      assert Igniter.Libs.Phoenix.web_module?("TestWeb")
      assert Igniter.Libs.Phoenix.web_module?("AdminWeb")
      assert Igniter.Libs.Phoenix.web_module?("MyAppWeb")
    end

    test "returns false for invalid web modules (atoms)" do
      # Two levels deep
      refute Igniter.Libs.Phoenix.web_module?(Foo.BarWeb)
      # Doesn't end with Web
      refute Igniter.Libs.Phoenix.web_module?(TestController)
      # Doesn't end with Web
      refute Igniter.Libs.Phoenix.web_module?(NotWebModule)
      # Nil
      refute Igniter.Libs.Phoenix.web_module?(nil)
    end

    test "returns false for invalid web modules (strings)" do
      # Two levels deep
      refute Igniter.Libs.Phoenix.web_module?("Foo.BarWeb")
      # Doesn't end with Web
      refute Igniter.Libs.Phoenix.web_module?("TestController")
      # Doesn't end with Web
      refute Igniter.Libs.Phoenix.web_module?("NotWebModule")
      # Invalid string format
      refute Igniter.Libs.Phoenix.web_module?("not.a.valid.module")
    end

    test "returns false for other types" do
      refute Igniter.Libs.Phoenix.web_module?(123)
      refute Igniter.Libs.Phoenix.web_module?([])
      refute Igniter.Libs.Phoenix.web_module?(%{})
    end
  end

  describe "list_routers/1" do
    test "finds routers using any valid web module" do
      igniter =
        assert test_project()
               |> Igniter.create_new_file("lib/test_web.ex", """
               defmodule TestWeb do
                 use Phoenix.Web
               end
               """)
               |> Igniter.create_new_file("lib/admin_web.ex", """
               defmodule AdminWeb do
                 use Phoenix.Web
               end
               """)
               |> Igniter.create_new_file("lib/test_web/router.ex", """
               defmodule TestWeb.Router do
                 use TestWeb, :router
               end
               """)
               |> Igniter.create_new_file("lib/admin_web/router.ex", """
               defmodule AdminWeb.Router do
                 use AdminWeb, :router
               end
               """)
               |> Igniter.create_new_file("lib/foo/bar_web/router.ex", """
               defmodule Foo.BarWeb.Router do
                 use Foo.BarWeb, :router
               end
               """)
               |> Igniter.create_new_file("lib/not_a_router.ex", """
               defmodule NotARouter do
                 use TestWeb, :controller
               end
               """)
               |> apply_igniter!()

      {_igniter, routers} = Igniter.Libs.Phoenix.list_routers(igniter)

      # Should include routers that use valid web modules
      assert TestWeb.Router in routers
      assert AdminWeb.Router in routers

      # Should exclude modules that aren't routers
      refute NotARouter in routers

      # Verify exact count
      assert length(routers) == 3
    end

    test "falls back to Phoenix.Router detection when no web module match" do
      igniter =
        assert test_project()
               |> Igniter.create_new_file("lib/plain_router.ex", """
               defmodule PlainRouter do
                 use Phoenix.Router
               end
               """)
               |> apply_igniter!()

      {_igniter, routers} = Igniter.Libs.Phoenix.list_routers(igniter)

      assert PlainRouter in routers
      assert length(routers) == 1
    end
  end

  describe "add_scope/4" do
    setup do
      router = """
      defmodule TestWeb.Router do
        use TestWeb, :router

        pipeline :browser do
          plug :accepts, ["html"]
        end

        scope "/", TestWeb do
          pipe_through :browser
          get "/", PageController, :home
        end

        if Application.compile_env(:test, :dev_routes) do
          scope "/dev" do
            pipe_through :browser
            live_dashboard "/dashboard", metrics: TestWeb.Telemetry
          end
        end
      end
      """

      igniter =
        assert test_project()
               |> Igniter.create_or_update_elixir_file(
                 "lib/test_web/router.ex",
                 router,
                 &{:ok, Igniter.Code.Common.replace_code(&1, router)}
               )
               |> apply_igniter!()

      {igniter, router} = Igniter.Libs.Phoenix.select_router(igniter)

      [igniter: igniter, router: router]
    end

    test "before existing scopes", %{igniter: igniter, router: router} do
      igniter
      |> Igniter.Libs.Phoenix.add_scope(
        "/test",
        """
        get "/", TestController, :test
        """,
        router: router,
        placement: :before
      )
      |> assert_has_patch("lib/test_web/router.ex", """
         8 + |  scope "/test" do
         9 + |    get("/", TestController, :test)
        10 + |  end
        11 + |
      8 12   |  scope "/", TestWeb do
      """)
    end

    test "after existing scopes", %{igniter: igniter, router: router} do
      igniter
      |> Igniter.Libs.Phoenix.append_to_scope(
        "/test",
        """
        get "/", TestController, :test
        """,
        router: router,
        placement: :after
      )
      |> assert_has_patch("lib/test_web/router.ex", """
      18 18   |  end
         19 + |
         20 + |  scope "/test" do
         21 + |    get("/", TestController, :test)
         22 + |  end
      19 23   |end
      """)
    end
  end

  describe "append_to_scope/4" do
    setup do
      router = """
      defmodule TestWeb.Router do
        use TestWeb, :router

        pipeline :browser do
          plug :accepts, ["html"]
        end

        scope "/", TestWeb do
          pipe_through :browser
          get "/", PageController, :home
        end

        if Application.compile_env(:test, :dev_routes) do
          scope "/dev" do
            pipe_through :browser
            live_dashboard "/dashboard", metrics: TestWeb.Telemetry
          end
        end
      end
      """

      igniter =
        assert test_project()
               |> Igniter.create_or_update_elixir_file(
                 "lib/test_web/router.ex",
                 router,
                 &{:ok, Igniter.Code.Common.replace_code(&1, router)}
               )
               |> apply_igniter!()

      {igniter, router} = Igniter.Libs.Phoenix.select_router(igniter)

      [igniter: igniter, router: router]
    end

    test "update matching scope", %{igniter: igniter, router: router} do
      igniter
      |> Igniter.Libs.Phoenix.append_to_scope(
        "/",
        """
        get "/", TestController, :test
        """,
        router: router,
        arg2: Igniter.Libs.Phoenix.web_module(igniter),
        with_pipelines: [:browser],
        placement: :before
      )
      |> assert_has_patch("lib/test_web/router.ex", """
       9  9   |    pipe_through(:browser)
      10 10   |    get("/", PageController, :home)
         11 + |    get("/", TestController, :test)
      """)
    end

    test "before existing scopes when no one matches", %{igniter: igniter, router: router} do
      igniter
      |> Igniter.Libs.Phoenix.append_to_scope(
        "/test",
        """
        get "/", TestController, :test
        """,
        router: router,
        with_pipelines: [:browser],
        placement: :before
      )
      |> assert_has_patch("lib/test_web/router.ex", """
         8 + |  scope "/test" do
         9 + |    pipe_through([:browser])
        10 + |    get("/", TestController, :test)
        11 + |  end
        12 + |
      8 13   |  scope "/", TestWeb do
      """)
    end

    test "after existing scopes when no one matches", %{igniter: igniter, router: router} do
      igniter
      |> Igniter.Libs.Phoenix.append_to_scope(
        "/test",
        """
        get "/", TestController, :test
        """,
        router: router,
        with_pipelines: [:browser],
        placement: :after
      )
      |> assert_has_patch("lib/test_web/router.ex", """
      18 18   |  end
         19 + |
         20 + |  scope "/test" do
         21 + |    pipe_through([:browser])
         22 + |    get("/", TestController, :test)
         23 + |  end
      19 24   |end
      """)
    end
  end
end
