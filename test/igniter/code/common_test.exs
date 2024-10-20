defmodule Igniter.Code.CommonTest do
  alias Sourceror.Zipper
  use ExUnit.Case
  require Igniter.Code.Function

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

  describe "add_code" do
    test "adding multiple blocks" do
      zipper =
        """
        defmodule Foo do
          alias Foo.Bar
          alias Foo.Bar.Baz

          if foo do
            random = "what"
            url = "url"
          end
        end
        """
        |> Sourceror.parse_string!()
        |> Sourceror.Zipper.zip()

      with {:ok, zipper} <- Igniter.Code.Module.move_to_defmodule(zipper),
           {:ok, zipper} <- Igniter.Code.Common.move_to_do_block(zipper),
           {:ok, zipper} <-
             Igniter.Code.Function.move_to_function_call_in_current_scope(zipper, :if, 2),
           {:ok, zipper} <- Igniter.Code.Common.move_to_do_block(zipper),
           {:ok, zipper} <-
             Igniter.Code.Function.move_to_function_call(zipper, :=, 2, fn call ->
               Igniter.Code.Function.argument_matches_pattern?(
                 call,
                 0,
                 {:url, _, ctx} when is_atom(ctx)
               )
             end) do
        assert zipper
               |> Igniter.Project.Config.modify_configuration_code(
                 [Foo, :url],
                 :app,
                 {:url, [], nil}
               )
               |> Sourceror.Zipper.top()
               |> Igniter.Util.Debug.code_at_node() ==
                 String.trim_trailing("""
                 defmodule Foo do
                   alias Foo.Bar
                   alias Foo.Bar.Baz

                   if foo do
                     random = "what"
                     url = "url"
                     config :app, Foo, url: url
                   end
                 end
                 """)
      else
        _ ->
          flunk("Should not reach this case")
      end
    end
  end

  describe "update_all_matches" do
    test "code can be removed" do
      source =
        """
        attributes do
          attribute :label, :string, required: true
          attribute :key, :string, :last_arg_seems_to_stick
          attribute :data, :villain
          attribute :key, :string, :another_one_that_sticks
          attribute :data, :villain
        end
        """

      zipper =
        source
        |> Sourceror.parse_string!()
        |> Zipper.zip()

      {:ok, zipper} =
        Igniter.Code.Common.update_all_matches(
          zipper,
          fn z ->
            Igniter.Code.Function.function_call?(z, :attribute, 2) &&
              Igniter.Code.Function.argument_equals?(z, 1, :villain)
          end,
          fn zipper ->
            zipper
            |> Zipper.remove()
            |> then(&{:ok, &1})
          end
        )

      assert Sourceror.to_string(zipper.node) ==
               """
               attributes do
                 attribute(:label, :string, required: true)
                 attribute(:key, :string, :last_arg_seems_to_stick)
                 attribute(:key, :string, :another_one_that_sticks)
               end
               """
               |> String.trim_trailing()
    end

    test "code can be replaced" do
      source =
        """
        attributes do
          attribute :label, :string, required: true
          attribute :key, :string, :last_arg_seems_to_stick
          attribute :data, :villain
          attribute :key, :string, :another_one_that_sticks
          attribute :data, :villain
        end
        """

      zipper =
        source
        |> Sourceror.parse_string!()
        |> Zipper.zip()

      {:ok, zipper} =
        Igniter.Code.Common.update_all_matches(
          zipper,
          fn z ->
            Igniter.Code.Function.function_call?(z, :attribute, 2) &&
              Igniter.Code.Function.argument_equals?(z, 1, :villain)
          end,
          fn zipper ->
            {:ok,
             Zipper.replace(
               zipper,
               quote do
                 testing(:code_insertion)
               end
             )}
          end
        )

      assert Sourceror.to_string(zipper.node) ==
               """
               attributes do
                 attribute(:label, :string, required: true)
                 attribute(:key, :string, :last_arg_seems_to_stick)
                 testing(:code_insertion)
                 attribute(:key, :string, :another_one_that_sticks)
                 testing(:code_insertion)
               end
               """
               |> String.trim_trailing()
    end

    test "code can be replaced with multi line replacement" do
      source =
        """
        listings do
          query %{status: :published, order: "asc sequence"}
          filters([
            [label: :name, filter: "name"],
            [label: :status, filter: "status"]
          ])
        end
        """

      zipper =
        source
        |> Sourceror.parse_string!()
        |> Zipper.zip()

      {:ok, zipper} =
        Igniter.Code.Common.update_all_matches(
          zipper,
          fn z ->
            Igniter.Code.Function.function_call?(z, :filters, 1)
          end,
          fn zipper ->
            {:ok,
             Igniter.Code.Common.replace_code(
               zipper,
               quote do
                 filter(:status)
                 filter(:order)
               end
             )}
          end
        )

      assert Sourceror.to_string(zipper.node) ==
               """
               listings do
                 query(%{status: :published, order: "asc sequence"})
                 filter(:status)
                 filter(:order)
               end
               """
               |> String.trim_trailing()
    end
  end
end
