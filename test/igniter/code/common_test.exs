defmodule Igniter.Code.CommonTest do
  use ExUnit.Case

  describe "topmost/1" do
    test "escapes subtrees using `within`" do
      """
      [
        [1, 2, 3],
        [4, 5, 6]
      ]
      """
      |> Sourceror.parse_string!()
      |> Sourceror.Zipper.zip()
      |> Sourceror.Zipper.down()
      |> Sourceror.Zipper.down()
      |> Igniter.Code.Common.within(fn zipper ->
        send(self(), {:zipper, Sourceror.Zipper.topmost(zipper)})

        {:ok, zipper}
      end)

      assert_received {:zipper, zipper}

      assert Igniter.Util.Debug.code_at_node(zipper) ==
               String.trim_trailing("""
               [
                 [1, 2, 3],
                 [4, 5, 6]
               ]
               """)
    end
  end

  describe "move_to_cursor_match_in_scope/1" do
    test "escapes subtrees using `within`" do
      pattern = """
      if config_env() == :prod do
        __cursor__()
      end
      """

      assert {:ok, zipper} =
               """
               foo = 10

               bar = 12

               if config_env() == :prod do
                 12
               end
               """
               |> Sourceror.parse_string!()
               |> Sourceror.Zipper.zip()
               |> Igniter.Code.Common.move_to_cursor_match_in_scope(pattern)

      assert Igniter.Util.Debug.code_at_node(zipper) == "12"
    end
  end

  describe "current_env/2" do
    test "knows about aliases" do
      zipper =
        """
        defmodule Foo do
          alias Foo.Bar.Baz

          [Baz]
        end
        """
        |> Sourceror.parse_string!()
        |> Sourceror.Zipper.zip()

      with {:ok, zipper} <- Igniter.Code.Module.move_to_defmodule(zipper),
           {:ok, zipper} <- Igniter.Code.Common.move_to_do_block(zipper),
           {:ok, zipper} <- Igniter.Code.Common.move_right(zipper, &Igniter.Code.List.list?/1),
           {:ok, zipper} <- Igniter.Code.List.prepend_new_to_list(zipper, Foo.Bar.Baz) do
        assert zipper
               |> Sourceror.Zipper.top()
               |> Igniter.Util.Debug.code_at_node() ==
                 String.trim_trailing("""
                 defmodule Foo do
                   alias Foo.Bar.Baz

                   [Baz]
                 end
                 """)
      else
        _ ->
          flunk("Should not reach this case")
      end
    end

    test "uses existing aliases" do
      zipper =
        """
        defmodule Foo do
          alias Foo.Bar
          alias Foo.Bar.Baz

          [Baz]
        end
        """
        |> Sourceror.parse_string!()
        |> Sourceror.Zipper.zip()

      with {:ok, zipper} <- Igniter.Code.Module.move_to_defmodule(zipper),
           {:ok, zipper} <- Igniter.Code.Common.move_to_do_block(zipper),
           {:ok, zipper} <- Igniter.Code.Common.move_right(zipper, &Igniter.Code.List.list?/1),
           {:ok, zipper} <- Igniter.Code.List.prepend_new_to_list(zipper, Foo.Bar.Baz) do
        assert zipper
               |> Igniter.Code.Common.add_code("[Foo.Bar.Baz.Blart]")
               |> Sourceror.Zipper.top()
               |> Igniter.Util.Debug.code_at_node() ==
                 String.trim_trailing("""
                 defmodule Foo do
                   alias Foo.Bar
                   alias Foo.Bar.Baz

                   [Baz]
                   [Baz.Blart]
                 end
                 """)
      else
        _ ->
          flunk("Should not reach this case")
      end
    end
  end
end
