defmodule Igniter.Code.WithinTest do
  alias Igniter.Code.Common
  alias Sourceror.Zipper
  use ExUnit.Case
  import Igniter.Test

  describe "with within" do
    test "performs multiple changes to some module" do
      test_project()
      |> Igniter.create_new_file("lib/some_module.ex", """
      defmodule SomeModule do
        alias Some.Example

        def some_function(a, b) do
          Example.function(a, b)
        end
      end
      """)
      |> apply_igniter!()
      |> Igniter.Project.Module.find_and_update_module!(SomeModule, fn zipper ->
        zipper
        |> within!(fn zipper ->
          pred = &match?(%Zipper{node: {:alias, _, _}}, &1)
          zipper = Common.remove(zipper, pred)
          line = "import Some.Example, only: [:function]"
          {:ok, Common.add_code(zipper, line, placement: :before)}
        end)
        |> within!(fn zipper ->
          {:ok, zipper} = move_to_function(zipper, :some_function)
          {:ok, zipper} = Common.move_to_do_block(zipper)
          line = "my_private_function!(function(a, b))"
          {:ok, Igniter.Code.Common.replace_code(zipper, line)}
        end)
        |> within!(fn zipper ->
          block = """
          defp private_function!({:ok, result}), do: result
          defp private_function!(_), do: raise "Something went wrong!"
          """

          {:ok, Common.add_code(zipper, block, placement: :after)}
        end)
        |> then(fn zipper -> {:ok, zipper} end)
      end)
      |> Igniter.Refactors.Rename.rename_function(
        {SomeModule, :some_function},
        {SomeModule, :some_function!},
        arity: 2
      )
      |> assert_has_patch("lib/some_module.ex", """
          |defmodule SomeModule do
        - |  alias Some.Example
        + |  import Some.Example, only: [:function]
          |
        - |  def some_function(a, b) do
        - |    Example.function(a, b)
        + |  def some_function!(a, b) do
        + |    my_private_function!(function(a, b))
          |  end
        + |
        + |  defp private_function!({:ok, result}),
        + |    do: result
        + |
        + |  defp private_function!(_),
        + |    do: raise("Something went wrong!")
          |end
      """)
    end
  end

  defp within!(zipper, function) do
    case Common.within(zipper, function) do
      {:ok, zipper} -> zipper
      :error -> raise "Error calling within"
    end
  end

  defp move_to_function(zipper, function) do
    Igniter.Code.Common.move_to(zipper, fn zipper ->
      Igniter.Code.Function.function_call?(zipper, function)
    end)
  end
end
