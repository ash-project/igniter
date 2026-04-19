# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Igniter.Refactors.RenameTest do
  use ExUnit.Case
  import Igniter.Test

  defmodule Elixir.SomeModule do
    def some_function(a, b), do: a + b
  end

  test "performs a simple rename on zero arity functions" do
    test_project()
    |> Igniter.create_new_file("lib/example.ex", """
    defmodule Example do
      SomeModule.some_function()
    end
    """)
    |> apply_igniter!()
    |> Igniter.Refactors.Rename.rename_function(
      {SomeModule, :some_function},
      {SomeOtherModule, :some_other_function},
      arity: 0
    )
    |> assert_has_patch("lib/example.ex", """
    - |  SomeModule.some_function()
    + |  SomeOtherModule.some_other_function()
    """)
  end

  test "copies & deprecates the function, bringing docs and specs along for the ride" do
    test_project()
    |> Igniter.create_new_file("lib/example.ex", """
    defmodule Example do
      @doc "what"
      @spec some_function() :: :hello
      def some_function() do
        :hello
      end
    end
    """)
    |> apply_igniter!()
    |> Igniter.Refactors.Rename.rename_function(
      {Example, :some_function},
      {Example, :some_other_function},
      arity: 0,
      deprecate: :hard
    )
    |> assert_content_equals("lib/example.ex", """
    defmodule Example do
      @doc "what"
      @spec some_other_function() :: :hello
      def some_other_function() do
        :hello
      end

      @doc "what"
      @spec some_function() :: :hello
      @deprecated "Use `some_other_function/0` instead."
      def some_function() do
        :hello
      end
    end
    """)
  end

  test "copies & soft deprecates the function, bringing docs and specs along for the ride" do
    test_project()
    |> Igniter.create_new_file("lib/example.ex", """
    defmodule Example do
      @doc "what"
      @spec some_function() :: :hello
      def some_function() do
        :hello
      end
    end
    """)
    |> apply_igniter!()
    |> Igniter.Refactors.Rename.rename_function(
      {Example, :some_function},
      {Example, :some_other_function},
      arity: 0,
      deprecate: :soft
    )
    |> assert_content_equals("lib/example.ex", """
    defmodule Example do
      @doc "what"
      @spec some_other_function() :: :hello
      def some_other_function() do
        :hello
      end

      @doc "what"
      @spec some_function() :: :hello
      @doc deprecated: "Use `some_other_function/0` instead."
      def some_function() do
        :hello
      end
    end
    """)
  end

  test "replaces the function if its not being deprecated" do
    test_project()
    |> Igniter.create_new_file("lib/example.ex", """
    defmodule Example do
      @doc "what"
      @spec some_function() :: :hello
      def some_function() do
        :hello
      end
    end
    """)
    |> apply_igniter!()
    |> Igniter.Refactors.Rename.rename_function(
      {Example, :some_function},
      {Example, :some_other_function}
    )
    |> assert_content_equals("lib/example.ex", """
    defmodule Example do
      @doc "what"
      @spec some_other_function() :: :hello
      def some_other_function() do
        :hello
      end
    end
    """)
  end

  test "performs a simple rename to a different module" do
    test_project()
    |> Igniter.create_new_file("lib/example.ex", """
    defmodule Example do
      @doc "what"
      @spec some_function() :: :hello
      def some_function() do
        :hello
      end
    end
    """)
    |> Igniter.create_new_file("lib/new_example.ex", """
    defmodule NewExample do
    end
    """)
    |> apply_igniter!()
    |> Igniter.Refactors.Rename.rename_function(
      {Example, :some_function},
      {NewExample, :some_other_function}
    )
    |> assert_content_equals("lib/example.ex", """
    defmodule Example do
    end
    """)
    |> assert_content_equals("lib/new_example.ex", """
    defmodule NewExample do
      @doc "what"
      @spec some_other_function() :: :hello
      def some_other_function() do
        :hello
      end
    end
    """)
  end

  test "performs a simple rename on two arity functions" do
    test_project()
    |> Igniter.create_new_file("lib/example.ex", """
    defmodule Example do
      SomeModule.some_function(1, 2)
    end
    """)
    |> apply_igniter!()
    |> Igniter.Refactors.Rename.rename_function(
      {SomeModule, :some_function},
      {SomeOtherModule, :some_other_function},
      arity: 2
    )
    |> assert_has_patch("lib/example.ex", """
    - |  SomeModule.some_function(1, 2)
    + |  SomeOtherModule.some_other_function(1, 2)
    """)
  end

  test "performs a simple rename on piped module call functions" do
    test_project()
    |> Igniter.create_new_file("lib/example.ex", """
    defmodule Example do
      1
      |> SomeModule.some_function(2)
    end
    """)
    |> apply_igniter!()
    |> Igniter.Refactors.Rename.rename_function(
      {SomeModule, :some_function},
      {SomeOtherModule, :some_other_function},
      arity: 2
    )
    |> assert_has_patch("lib/example.ex", """
    - | |> SomeModule.some_function(2)
    + | |> SomeOtherModule.some_other_function(2)
    """)
  end

  test "can detect aliases" do
    test_project()
    |> Igniter.create_new_file("lib/example.ex", """
    defmodule Example do
      alias SomeModule, as: SomethingElse

      SomethingElse.some_function(1, 2)
    end
    """)
    |> apply_igniter!()
    |> Igniter.Refactors.Rename.rename_function(
      {SomeModule, :some_function},
      {SomeOtherModule, :some_other_function},
      arity: 2
    )
    |> assert_has_patch("lib/example.ex", """
    - |  SomethingElse.some_function(1, 2)
    + |  SomeOtherModule.some_other_function(1, 2)
    """)
  end

  test "can detect imports" do
    test_project()
    |> Igniter.create_new_file("lib/example.ex", """
    defmodule Example do
      import SomeModule

      some_function(1, 2)
    end
    """)
    |> apply_igniter!()
    |> Igniter.Refactors.Rename.rename_function(
      {SomeModule, :some_function},
      {SomeOtherModule, :some_other_function},
      arity: 2
    )
    |> assert_has_patch("lib/example.ex", """
    - |  some_function(1, 2)
    + |  SomeOtherModule.some_other_function(1, 2)
    """)
  end

  test "will rewrite the definitions within the module" do
    test_project()
    |> Igniter.create_new_file("lib/some_module.ex", """
    defmodule SomeModule do
      def some_function(a, b), do: a + b
    end
    """)
    |> Igniter.create_new_file("lib/example.ex", """
    defmodule Example do
      import SomeModule

      some_function(1, 2)
    end
    """)
    |> apply_igniter!()
    |> Igniter.Refactors.Rename.rename_function(
      {SomeModule, :some_function},
      {SomeModule, :some_other_function},
      arity: 2
    )
    |> assert_has_patch("lib/example.ex", """
    - |  some_function(1, 2)
    + |  some_other_function(1, 2)
    """)
    |> assert_has_patch("lib/some_module.ex", """
    - |  def some_function(a, b), do: a + b
    + |  def some_other_function(a, b), do: a + b
    """)
  end

  test "will rewrite function captures" do
    test_project()
    |> Igniter.create_new_file("lib/example.ex", """
    defmodule Example do
      import SomeModule

      def a_function do
        &some_function/2
        &SomeModule.some_function/2
        &some_function(&1, 10)
        &SomeModule.some_function(&1, 10)
      end
    end
    """)
    |> apply_igniter!()
    |> Igniter.Refactors.Rename.rename_function(
      {SomeModule, :some_function},
      {SomeModule, :some_other_function},
      arity: 2
    )
    |> assert_has_patch("lib/example.ex", """
    - |  &some_function/2
    - |  &SomeModule.some_function/2
    - |  &some_function(&1, 10)
    - |  &SomeModule.some_function(&1, 10)
    + |  &some_other_function/2
    + |  &SomeModule.some_other_function/2
    + |  &some_other_function(&1, 10)
    + |  &SomeModule.some_other_function(&1, 10)
    """)
  end

  describe "rename_module" do
    test "renames the defmodule declaration" do
      test_project()
      |> Igniter.create_new_file("lib/example.ex", """
      defmodule Example do
        def hello, do: :world
      end
      """)
      |> apply_igniter!()
      |> Igniter.Refactors.Rename.rename_module(Example, NewExample)
      |> assert_has_patch("lib/example.ex", "- |defmodule Example do\n+ |defmodule NewExample do")
    end

    test "moves the file to the correct path" do
      test_project()
      |> Igniter.create_new_file("lib/example.ex", """
      defmodule Example do
      end
      """)
      |> apply_igniter!()
      |> Igniter.Refactors.Rename.rename_module(Example, NewExample)
      |> assert_moves("lib/example.ex", "lib/new_example.ex")
    end

    test "updates alias in another file" do
      test_project()
      |> Igniter.create_new_file("lib/example.ex", "defmodule Example do\nend\n")
      |> Igniter.create_new_file("lib/consumer.ex", """
      defmodule Consumer do
        alias Example
        def run, do: Example.hello()
      end
      """)
      |> apply_igniter!()
      |> Igniter.Refactors.Rename.rename_module(Example, NewExample)
      |> assert_has_patch("lib/consumer.ex", "+ |  alias NewExample")
    end

    test "updates use in another file" do
      test_project()
      |> Igniter.create_new_file("lib/example.ex", "defmodule Example do\nend\n")
      |> Igniter.create_new_file("lib/consumer.ex", """
      defmodule Consumer do
        use Example
      end
      """)
      |> apply_igniter!()
      |> Igniter.Refactors.Rename.rename_module(Example, NewExample)
      |> assert_has_patch("lib/consumer.ex", "+ |  use NewExample")
    end

    test "updates import in another file" do
      test_project()
      |> Igniter.create_new_file("lib/example.ex", "defmodule Example do\nend\n")
      |> Igniter.create_new_file("lib/consumer.ex", """
      defmodule Consumer do
        import Example
      end
      """)
      |> apply_igniter!()
      |> Igniter.Refactors.Rename.rename_module(Example, NewExample)
      |> assert_has_patch("lib/consumer.ex", "+ |  import NewExample")
    end

    test "updates require in another file" do
      test_project()
      |> Igniter.create_new_file("lib/example.ex", "defmodule Example do\nend\n")
      |> Igniter.create_new_file("lib/consumer.ex", """
      defmodule Consumer do
        require Example
      end
      """)
      |> apply_igniter!()
      |> Igniter.Refactors.Rename.rename_module(Example, NewExample)
      |> assert_has_patch("lib/consumer.ex", "+ |  require NewExample")
    end

    test "renames a submodule along with the parent" do
      test_project()
      |> Igniter.create_new_file("lib/example.ex", "defmodule Example do\nend\n")
      |> Igniter.create_new_file("lib/example/worker.ex", """
      defmodule Example.Worker do
        alias Example
      end
      """)
      |> apply_igniter!()
      |> Igniter.Refactors.Rename.rename_module(Example, NewExample)
      |> assert_has_patch("lib/example/worker.ex", "+ |defmodule NewExample.Worker do")
      |> assert_moves("lib/example/worker.ex", "lib/new_example/worker.ex")
    end

    test "renames the corresponding test module" do
      test_project()
      |> Igniter.create_new_file("lib/example.ex", "defmodule Example do\nend\n")
      |> Igniter.create_new_file("test/example_test.exs", """
      defmodule ExampleTest do
        use ExUnit.Case
        alias Example
      end
      """)
      |> apply_igniter!()
      |> Igniter.Refactors.Rename.rename_module(Example, NewExample)
      |> assert_has_patch(
        "test/example_test.exs",
        "- |defmodule ExampleTest do\n+ |defmodule NewExampleTest do"
      )
    end

    test "updates string references in moduledoc" do
      test_project()
      |> Igniter.create_new_file("lib/example.ex", """
      defmodule Example do
        @moduledoc "See Example for details."
      end
      """)
      |> apply_igniter!()
      |> Igniter.Refactors.Rename.rename_module(Example, NewExample)
      |> assert_has_patch("lib/example.ex", "+ |  @moduledoc \"See NewExample for details.\"")
    end

    test "does not rename unrelated alias that shares only the last segment" do
      test_project()
      |> Igniter.create_new_file(
        "lib/some/other/example.ex",
        "defmodule Some.Other.Example do\nend\n"
      )
      |> Igniter.create_new_file("lib/consumer.ex", """
      defmodule Consumer do
        alias MyApp.Example

        def run do
          Example.local()
          Some.Other.Example.remote()
        end
      end
      """)
      |> apply_igniter!()
      |> Igniter.Refactors.Rename.rename_module(Some.Other.Example, Some.Other.NewExample)
      |> assert_has_patch(
        "lib/consumer.ex",
        "- |      Some.Other.Example.remote()\n+ |      Some.Other.NewExample.remote()"
      )
    end

    test "renames short form when the file explicitly aliases the renamed module" do
      test_project()
      |> Igniter.create_new_file("lib/some_module.ex", "defmodule SomeModule do\nend\n")
      |> Igniter.create_new_file("lib/example.ex", """
      defmodule Example do
        alias SomeModule

        def run, do: SomeModule.hello()
      end
      """)
      |> apply_igniter!()
      |> Igniter.Refactors.Rename.rename_module(SomeModule, SomeOtherModule)
      |> assert_has_patch("lib/example.ex", "- |  alias SomeModule\n+ |  alias SomeOtherModule")
      |> assert_has_patch(
        "lib/example.ex",
        "- |  def run, do: SomeModule.hello()\n+ |  def run, do: SomeOtherModule.hello()"
      )
    end

    test "renames short form and updates declaration for multi-alias" do
      test_project()
      |> Igniter.create_new_file("lib/some_module.ex", "defmodule SomeModule do\nend\n")
      |> Igniter.create_new_file("lib/example.ex", """
      defmodule Example do
        alias MyApp.{SomeModule, OtherModule}

        def run, do: SomeModule.hello()
      end
      """)
      |> apply_igniter!()
      |> Igniter.Refactors.Rename.rename_module(MyApp.SomeModule, MyApp.SomeOtherModule)
      |> assert_has_patch(
        "lib/example.ex",
        "- |  alias MyApp.{SomeModule, OtherModule}\n+ |  alias MyApp.{SomeOtherModule, OtherModule}"
      )
      |> assert_has_patch(
        "lib/example.ex",
        "- |  def run, do: SomeModule.hello()\n+ |  def run, do: SomeOtherModule.hello()"
      )
    end

    test "does not rename custom as: alias call sites" do
      test_project()
      |> Igniter.create_new_file("lib/some_module.ex", "defmodule SomeModule do\nend\n")
      |> Igniter.create_new_file("lib/example.ex", """
      defmodule Example do
        alias SomeModule, as: S

        def run, do: S.hello()
      end
      """)
      |> apply_igniter!()
      |> Igniter.Refactors.Rename.rename_module(SomeModule, SomeOtherModule)
      |> assert_has_patch(
        "lib/example.ex",
        "- |  alias SomeModule, as: S\n+ |  alias SomeOtherModule, as: S"
      )
    end
  end
end
