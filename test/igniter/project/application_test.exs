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
  end
end
