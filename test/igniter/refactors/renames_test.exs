defmodule Igniter.Refactors.RenameTest do
  use ExUnit.Case
  import Igniter.Test

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
      0
    )
    |> assert_has_patch("lib/example.ex", """
    - |  SomeModule.some_function()
    + |  SomeOtherModule.some_other_function()
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
      2
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
      2
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
      2
    )
    |> assert_has_patch("lib/example.ex", """
    - |  SomethingElse.some_function(1, 2)
    + |  SomeOtherModule.some_other_function(1, 2)
    """)
  end

  @tag :focus
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
      2
    )
    |> assert_has_patch("lib/example.ex", """
    - |  some_function(1, 2)
    + |  SomeOtherModule.some_other_function(1, 2)
    """)
  end
end
