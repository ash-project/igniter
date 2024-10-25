defmodule Igniter.Refactors.RenameTest do
  use ExUnit.Case
  import Igniter.Test

  defmodule Elixir.SomeModule do
    def some_function(a, b), do: a + b
  end

  test "performs a simple rename on zero arity functions" do
    mix_project()
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

  test "performs a simple rename on two arity functions" do
    mix_project()
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
    mix_project()
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
    mix_project()
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
    mix_project()
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
    mix_project()
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
    mix_project()
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
