defmodule Igniter.Code.FunctionTest do
  use ExUnit.Case

  describe "move_to_function_call_in_current_scope/4" do
    test "works on its own" do
      assert {:ok, zipper} =
               """
               x = 5
               """
               |> Sourceror.parse_string!()
               |> Sourceror.Zipper.zip()
               |> Igniter.Code.Function.move_to_function_call_in_current_scope(:=, 2)

      assert Igniter.Debug.code_at_node(zipper) == "x = 5"
    end

    test "works when composed inside of a block" do
      assert {:ok, zipper} =
               """
               def thing do
                x = 5

                other_code
               end
               """
               |> Sourceror.parse_string!()
               |> Sourceror.Zipper.zip()
               |> Igniter.Code.Module.move_to_def(:thing, 0)

      assert {:ok, zipper} =
               Igniter.Code.Function.move_to_function_call_in_current_scope(zipper, :=, 2)

      assert Igniter.Debug.code_at_node(zipper) == "x = 5"
    end
  end
end
