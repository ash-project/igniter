defmodule Igniter.Project.ApplicationTest do
  use ExUnit.Case
  import Igniter.Test

  describe "add_new_child/1" do
    test "adds an application if one doesn't exist" do
      test_project()
      |> Igniter.Project.Application.add_new_child(Foo)
      |> assert_creates("lib/test/application.ex", """
      defmodule Test.Application do
        @moduledoc false

        use Application

        @impl true
        def start(_type, _args) do
          children = [Foo]

          opts = [strategy: :one_for_one, name: Test.Supervisor]
          Supervisor.start_link(children, opts)
        end
      end
      """)
      |> assert_has_patch("mix.exs", """
      17    - |      extra_applications: [:logger]
         17 + |      extra_applications: [:logger],
         18 + |      mod: {Test.Application, []}
      """)
    end

    test "doesnt add a module if its already supervised" do
      test_project()
      |> Igniter.Project.Application.add_new_child(Foo)
      |> apply_igniter!()
      |> Igniter.Project.Application.add_new_child(Foo)
      |> assert_unchanged()
    end

    test "doesnt add a module if its already supervised as a tuple" do
      test_project()
      |> Igniter.Project.Application.add_new_child({Foo, a: 1})
      |> apply_igniter!()
      |> Igniter.Project.Application.add_new_child(Foo)
      |> assert_unchanged()
    end

    test "doesnt add a module if its already supervised as an atom and we're adding a tuple" do
      test_project()
      |> Igniter.Project.Application.add_new_child(Foo)
      |> apply_igniter!()
      |> Igniter.Project.Application.add_new_child({Foo, a: 1})
      |> assert_unchanged()
    end

    test "supports taking options as the second argument" do
      test_project()
      |> Igniter.Project.Application.add_new_child({Foo, a: :b})
      |> assert_creates("lib/test/application.ex", """
      defmodule Test.Application do
        @moduledoc false

        use Application

        @impl true
        def start(_type, _args) do
          children = [{Foo, [a: :b]}]

          opts = [strategy: :one_for_one, name: Test.Supervisor]
          Supervisor.start_link(children, opts)
        end
      end
      """)
      |> assert_has_patch("mix.exs", """
      17    - |      extra_applications: [:logger]
         17 + |      extra_applications: [:logger],
         18 + |      mod: {Test.Application, []}
      """)
    end

    test "supports updating options using `opts_updater`" do
      test_project()
      |> Igniter.Project.Application.add_new_child({Foo, a: :b})
      |> apply_igniter!()
      |> Igniter.Project.Application.add_new_child(Foo,
        opts_updater: fn zipper ->
          Igniter.Code.Keyword.set_keyword_key(zipper, :c, :d)
        end
      )
      |> assert_has_patch("lib/test/application.ex", """
      8 - |    children = [{Foo, [a: :b]}]
      8 + |    children = [{Foo, [a: :b, c: :d]}]
      """)
    end

    test "will set opts to an empty list if using `opts_updater`" do
      test_project()
      |> Igniter.Project.Application.add_new_child(Foo)
      |> apply_igniter!()
      |> Igniter.Project.Application.add_new_child(Foo,
        opts_updater: fn zipper ->
          Igniter.Code.Keyword.set_keyword_key(zipper, :c, :d)
        end
      )
      |> assert_has_patch("lib/test/application.ex", """
      8 - |    children = [Foo]
      8 + |    children = [{Foo, [c: :d]}]
      """)
    end

    test "using `after: fn _ -> true end` with tuples in the list" do
      test_project()
      |> Igniter.Project.Application.add_new_child({Foo, a: :b})
      |> Igniter.Project.Application.add_new_child(Something)
      |> Igniter.Project.Application.add_new_child(SomethingAtTheEnd, after: fn _ -> true end)
      |> assert_creates("lib/test/application.ex", """
      defmodule Test.Application do
        @moduledoc false

        use Application

        @impl true
        def start(_type, _args) do
          children = [Something, {Foo, [a: :b]}, SomethingAtTheEnd]

          opts = [strategy: :one_for_one, name: Test.Supervisor]
          Supervisor.start_link(children, opts)
        end
      end
      """)
    end

    test "supports taking code as the second argument" do
      test_project()
      |> Igniter.Project.Application.add_new_child(
        {Foo,
         {:code,
          quote do
            [1 + 2]
          end}}
      )
      |> assert_creates("lib/test/application.ex", """
      defmodule Test.Application do
        @moduledoc false

        use Application

        @impl true
        def start(_type, _args) do
          children = [{Foo, [1 + 2]}]

          opts = [strategy: :one_for_one, name: Test.Supervisor]
          Supervisor.start_link(children, opts)
        end
      end
      """)
      |> assert_has_patch("mix.exs", """
      17    - |      extra_applications: [:logger]
         17 + |      extra_applications: [:logger],
         18 + |      mod: {Test.Application, []}
      """)
    end

    test "supports expressing " do
      :erlang.system_flag(:backtrace_depth, 1000)

      test_project()
      |> Igniter.Project.Application.add_new_child(Foo)
      |> apply_igniter!()
      |> Igniter.Project.Application.add_new_child(Bar)
      |> assert_has_patch("lib/test/application.ex", """
      8 - |    children = [Foo]
      8 + |    children = [Bar, Foo]
      """)
    end
  end

  describe "app_name/1" do
    test "it returns the application name when it's an atom literal" do
      igniter =
        test_project(
          files: %{
            "mix.exs" => """
            defmodule IgniterTest.MixProject do
              use Mix.Project

              def project do
                [
                  app: :igniter_test
                ]
              end
            end
            """
          }
        )

      assert Igniter.Project.Application.app_name(igniter) == :igniter_test
    end

    test "it returns the application name when it's a module attribute" do
      igniter =
        test_project(
          files: %{
            "mix.exs" => """
            defmodule IgniterTest.MixProject do
              use Mix.Project

              @app :igniter_test

              def project do
                [
                  app: @app
                ]
              end
            end
            """
          }
        )

      assert Igniter.Project.Application.app_name(igniter) == :igniter_test
    end

    test "it raises if the application name can't be resolved" do
      igniter =
        test_project(
          files: %{
            "mix.exs" => """
            defmodule IgniterTest.MixProject do
              use Mix.Project

              def project do
                [
                  app: app_name()
                ]
              end
            end
            """
          }
        )

      assert_raise RuntimeError, fn -> Igniter.Project.Application.app_name(igniter) end

      igniter =
        test_project(
          files: %{
            "mix.exs" => """
            defmodule IgniterTest.MixProject do
              use Mix.Project

              def project do
                [
                  app: @app
                ]
              end

              @app :igniter_test
            end
            """
          }
        )

      assert_raise RuntimeError, fn -> Igniter.Project.Application.app_name(igniter) end
    end
  end
end
