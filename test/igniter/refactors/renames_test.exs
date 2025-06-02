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
end
