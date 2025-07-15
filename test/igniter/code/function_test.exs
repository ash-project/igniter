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

      assert Igniter.Util.Debug.code_at_node(zipper) == "x = 5"
    end

    test "works on erlang modules calls" do
      assert {:ok, zipper} =
               """
               hello
               :logger.add_handler(1, 2, 3)
               world
               """
               |> Sourceror.parse_string!()
               |> Sourceror.Zipper.zip()
               |> Igniter.Code.Function.move_to_function_call_in_current_scope(
                 {:logger, :add_handler},
                 3
               )

      assert Igniter.Util.Debug.code_at_node(zipper) == ":logger.add_handler(1, 2, 3)"
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
               |> Igniter.Code.Function.move_to_def(:thing, 0)

      assert {:ok, zipper} =
               Igniter.Code.Function.move_to_function_call_in_current_scope(zipper, :=, 2)

      assert Igniter.Util.Debug.code_at_node(zipper) == "x = 5"
    end

    test "can be used to move multiple times" do
      assert {:ok, zipper} =
               """
               use Foo, [a: 1]
               use Bar, [a: 2]
               """
               |> Sourceror.parse_string!()
               |> Sourceror.Zipper.zip()
               |> Igniter.Code.Function.move_to_function_call_in_current_scope(:use, 2)

      zipper = Sourceror.Zipper.right(zipper)

      assert {:ok, zipper} =
               Igniter.Code.Function.move_to_function_call_in_current_scope(zipper, :use, 2)

      assert Igniter.Util.Debug.code_at_node(zipper) == "use Bar, a: 2"
    end
  end

  describe "move_to_def/3" do
    test "works with standard function definitions" do
      assert {:ok, zipper} =
               """
               defmodule Test do
                 def hello do
                   :world
                 end
               end
               """
               |> Sourceror.parse_string!()
               |> Sourceror.Zipper.zip()
               |> Igniter.Code.Function.move_to_def(:hello, 0)

      assert Igniter.Util.Debug.code_at_node(zipper) == ":world"
    end

    test "works with a function with zero arity and a guard" do
      assert {:ok, zipper} =
               """
               defmodule Test do
                 def hello when true do
                   :world
                 end
               end
               """
               |> Sourceror.parse_string!()
               |> Sourceror.Zipper.zip()
               |> Igniter.Code.Function.move_to_def(:hello, 0)

      assert Igniter.Util.Debug.code_at_node(zipper) == ":world"
    end

    test "works with a function with arity and a guard" do
      assert {:ok, zipper} =
               """
               defmodule Test do
                 def hello(x) when is_integer(x) do
                   :world
                 end
               end
               """
               |> Sourceror.parse_string!()
               |> Sourceror.Zipper.zip()
               |> Igniter.Code.Function.move_to_def(:hello, 1)

      assert Igniter.Util.Debug.code_at_node(zipper) == ":world"
    end

    test "proper inserts code into the function" do
      assert {:ok, zipper} =
               """
               defmodule Test do
                 def hello do
                   :world
                 end
               end
               """
               |> Sourceror.parse_string!()
               |> Sourceror.Zipper.zip()
               |> Igniter.Code.Function.move_to_def(:hello, 0, target: :inside)
               |> then(fn {:ok, zipper} ->
                 {:ok, Igniter.Code.Common.add_code(zipper, ":other_stuff", placement: :after)}
               end)

      assert Igniter.Util.Debug.code_at_node(Sourceror.Zipper.topmost(zipper)) ==
               """
               defmodule Test do
                 def hello do
                   :world
                   :other_stuff
                 end
               end
               """
               |> String.trim()
    end
  end

  describe "move_to_def/3 - target = :before" do
    test "works with no attrs in the function definition" do
      assert {:ok, zipper} =
               """
               defmodule Test do
                 def hello do
                   :world
                 end

                 def world do
                   :hello
                 end
               end
               """
               |> Sourceror.parse_string!()
               |> Sourceror.Zipper.zip()
               |> Igniter.Code.Function.move_to_def(:hello, 0, target: :before)

      assert Igniter.Util.Debug.code_at_node(zipper) == "def hello do\n  :world\nend"
    end

    test "works with docs in the function definition" do
      assert {:ok, zipper} =
               """
               defmodule Test do
                 @doc "hello"
                 def hello do
                   :world
                 end
               end
               """
               |> Sourceror.parse_string!()
               |> Sourceror.Zipper.zip()
               |> Igniter.Code.Function.move_to_def(:hello, 0, target: :before)

      assert Igniter.Util.Debug.code_at_node(zipper) ==
               "@doc \"hello\""
    end

    test "properly ignores non-function attributes" do
      assert {:ok, zipper} =
               """
               defmodule Test do
                 @moduledoc "hello"
                 @doc "world"
                 @spec hello :: :world
                 def hello do
                   :world
                 end
               end
               """
               |> Sourceror.parse_string!()
               |> Sourceror.Zipper.zip()
               |> Igniter.Code.Function.move_to_def(:hello, 0, target: :before)

      assert Igniter.Util.Debug.code_at_node(zipper) == "@doc \"world\""
    end

    test "matches function later in the module" do
      assert {:ok, zipper} =
               """
               defmodule Test do
                 @doc "hello"
                 def hello do
                   :world
                 end

                 @doc "world"
                 def world do
                   :hello
                 end
               end
               """
               |> Sourceror.parse_string!()
               |> Sourceror.Zipper.zip()
               |> Igniter.Code.Function.move_to_def(:world, 0, target: :before)

      assert Igniter.Util.Debug.code_at_node(zipper) == "@doc \"world\""
    end

    test "proper inserts code before the function" do
      assert {:ok, zipper} =
               """
               defmodule Test do
                 @doc "hello"
                 @impl true
                 def hello do
                   :world
                 end
               end
               """
               |> Sourceror.parse_string!()
               |> Sourceror.Zipper.zip()
               |> Igniter.Code.Function.move_to_def(:hello, 0, target: :before)
               |> then(fn {:ok, zipper} ->
                 {:ok,
                  Igniter.Code.Common.add_code(zipper, "def world do\n  :hello\nend",
                    placement: :before
                  )}
               end)

      assert Igniter.Util.Debug.code_at_node(Sourceror.Zipper.topmost(zipper)) ==
               """
               defmodule Test do
                 def world do
                   :hello
                 end

                 @doc "hello"
                 @impl true
                 def hello do
                   :world
                 end
               end
               """
               |> String.trim()
    end
  end

  describe "move_to_def/3 - target = :at" do
    test "works with no attrs in the function definition" do
      assert {:ok, zipper} =
               """
               defmodule Test do
                 @doc "hello"
                 def hello do
                   :world
                 end

                 def world do
                   :hello
                 end
               end
               """
               |> Sourceror.parse_string!()
               |> Sourceror.Zipper.zip()
               |> Igniter.Code.Function.move_to_def(:hello, 0, target: :at)

      assert Igniter.Util.Debug.code_at_node(zipper) == "def hello do\n  :world\nend"
    end

    test "proper inserts code after the function" do
      assert {:ok, zipper} =
               """
               defmodule Test do
                 def hello do
                   :world
                 end
               end
               """
               |> Sourceror.parse_string!()
               |> Sourceror.Zipper.zip()
               |> Igniter.Code.Function.move_to_def(:hello, 0, target: :at)
               |> then(fn {:ok, zipper} ->
                 {:ok,
                  Igniter.Code.Common.add_code(zipper, "def world do\n  :hello\nend",
                    placement: :after
                  )}
               end)

      assert Igniter.Util.Debug.code_at_node(Sourceror.Zipper.topmost(zipper)) ==
               """
               defmodule Test do
                 def hello do
                   :world
                 end

                 def world do
                   :hello
                 end
               end
               """
               |> String.trim()
    end
  end

  describe "function_call?/3" do
    test "works on calls with do blocks" do
      zipper =
        """
        fun 1 do
        end
        """
        |> Sourceror.parse_string!()
        |> Sourceror.Zipper.zip()

      assert Igniter.Code.Function.function_call?(zipper, :fun, [1, 2])
    end

    test "works on Kernel functions" do
      zipper =
        """
        1 ++ 2
        """
        |> Sourceror.parse_string!()
        |> Sourceror.Zipper.zip()

      assert Igniter.Code.Function.function_call?(zipper, {Kernel, :++})
    end
  end

  test "argument_equals?/3" do
    zipper =
      "config :key, Test"
      |> Sourceror.parse_string!()
      |> Sourceror.Zipper.zip()

    assert Igniter.Code.Function.argument_equals?(zipper, 0, :key) == true
    assert Igniter.Code.Function.argument_equals?(zipper, 0, Test) == false

    assert Igniter.Code.Function.argument_equals?(zipper, 1, :key) == false
    assert Igniter.Code.Function.argument_equals?(zipper, 1, Test) == true
  end
end
