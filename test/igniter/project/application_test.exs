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
end
