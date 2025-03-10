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
