# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Igniter.Code.ModuleTest do
  use ExUnit.Case

  import Igniter.Test

  doctest Igniter.Code.Module

  test "modules will be moved according to config" do
    %{rewrite: rewrite} =
      Igniter.new()
      |> Igniter.assign(:igniter_exs,
        module_location: :inside_matching_folder
      )
      |> Igniter.include_or_create_file("lib/foo/bar.ex", "defmodule Foo.Bar do\nend")
      |> Igniter.include_or_create_file(
        "lib/foo/bar/baz.ex",
        "defmodule Foo.Bar.Baz do\nend"
      )
      |> Igniter.prepare_for_write()

    paths = Rewrite.paths(rewrite)

    assert "lib/foo/bar/bar.ex" in paths
    assert "lib/foo/bar/baz.ex" in paths
  end

  test "module_names exact match mapping is used for destination path" do
    igniter =
      Igniter.new()
      |> Igniter.assign(:igniter_exs,
        module_location: :outside_matching_folder,
        module_names: [{"FooWeb.UserController", "lib/foo_web/controllers"}]
      )

    assert Igniter.Project.Module.proper_location(igniter, FooWeb.UserController) ==
             "lib/foo_web/controllers/user_controller.ex"
  end

  test "module_names regex mapping is used when exact mapping does not match" do
    igniter =
      Igniter.new()
      |> Igniter.assign(:igniter_exs,
        module_names: [{~r/^Foo\.Admin\./, "lib/foo_web/admin"}]
      )

    assert Igniter.Project.Module.proper_location(igniter, Foo.Admin.UsersController) ==
             "lib/foo_web/admin/users_controller.ex"
  end

  test "module_names exact mapping takes precedence over regex mapping" do
    igniter =
      Igniter.new()
      |> Igniter.assign(:igniter_exs,
        module_names: [
          {~r/^Foo\./, "lib/foo_web/default"},
          {"Foo.SpecialController", "lib/foo_web/controllers"}
        ]
      )

    assert Igniter.Project.Module.proper_location(igniter, Foo.SpecialController) ==
             "lib/foo_web/controllers/special_controller.ex"
  end

  test "proper_location falls back to module_location when no module_names entry matches" do
    igniter =
      Igniter.new()
      |> Igniter.assign(:igniter_exs,
        module_location: :outside_matching_folder,
        module_names: [{~r/^Other\./, "lib/other"}]
      )

    assert Igniter.Project.Module.proper_location(igniter, Foo.Bar.Baz) == "lib/foo/bar/baz.ex"
  end

  test "proper_location remains backwards compatible when module_names is not configured" do
    igniter = Igniter.new()

    assert Igniter.Project.Module.proper_location(igniter, Foo.Bar.Baz) == "lib/foo/bar/baz.ex"
  end

  test "modules can be found anywhere across the project" do
    %{rewrite: rewrite} =
      Igniter.new()
      |> Igniter.create_new_file("lib/foo/bar.ex", """
        defmodule Foo.Bar do
          defmodule Baz do
            10
          end
        end
      """)
      |> Igniter.Project.Module.find_and_update_or_create_module(
        Foo.Bar.Baz,
        """
        20
        """,
        fn zipper ->
          {:ok, Igniter.Code.Common.replace_code(zipper, 30)}
        end
      )

    contents =
      rewrite
      |> Rewrite.source!("lib/foo/bar.ex")
      |> Rewrite.Source.get(:content)

    assert contents == """
           defmodule Foo.Bar do
             defmodule Baz do
               30
             end
           end
           """
  end

  test "modules will be created if they do not exist, in the conventional place" do
    %{rewrite: rewrite} =
      Igniter.new()
      |> Igniter.create_new_file("lib/foo/bar.ex", """
      defmodule Foo.Bar do
      end
      """)
      |> Igniter.Project.Module.find_and_update_or_create_module(
        Foo.Bar.Baz,
        """
        20
        """,
        fn zipper ->
          {:ok, Igniter.Code.Common.replace_code(zipper, 30)}
        end
      )

    contents =
      rewrite
      |> Rewrite.source!("lib/foo/bar/baz.ex")
      |> Rewrite.Source.get(:content)

    assert contents == """
           defmodule Foo.Bar.Baz do
             20
           end
           """
  end

  test "modules will be created if they do not exist, in the conventional place, which can be configured" do
    %{rewrite: rewrite} =
      Igniter.new()
      |> Igniter.assign(:igniter_exs,
        module_location: :inside_matching_folder
      )
      |> Igniter.create_new_file("lib/foo/bar/something.ex", """
      defmodule Foo.Bar.Something do
      end
      """)
      |> Igniter.Project.Module.find_and_update_or_create_module(
        Foo.Bar,
        """
        20
        """,
        fn zipper ->
          {:ok, Igniter.Code.Common.replace_code(zipper, 30)}
        end
      )
      |> Igniter.prepare_for_write()

    contents =
      rewrite
      |> Rewrite.source!("lib/foo/bar/bar.ex")
      |> Rewrite.Source.get(:content)

    assert contents == """
           defmodule Foo.Bar do
             20
           end
           """
  end

  describe inspect(&Igniter.Code.Module.find_all_matching_modules/1) do
    test "finds all elixir files but ignores all other files" do
      igniter =
        test_project()
        |> Igniter.Project.Module.create_module(Foo, """
        defmodule Foo do
        end
        """)
        |> Igniter.create_new_file("test.txt", "Foo")

      assert {_igniter, [Foo, Test, Test.MixProject, TestTest]} =
               Igniter.Project.Module.find_all_matching_modules(igniter, fn _module, _zipper ->
                 true
               end)
    end
  end

  test "move_to_attribute_definition" do
    mod_zipper =
      ~s"""
      defmodule MyApp.Foo do
        @doc "My app module doc"
        @foo_key Application.compile_env!(:my_app, :key)
      end
      """
      |> Sourceror.parse_string!()
      |> Sourceror.Zipper.zip()

    assert {:ok, zipper} = Igniter.Code.Module.move_to_attribute_definition(mod_zipper, :doc)
    assert Igniter.Util.Debug.code_at_node(zipper) == ~s|@doc "My app module doc"|

    assert {:ok, zipper} = Igniter.Code.Module.move_to_attribute_definition(mod_zipper, :foo_key)

    assert Igniter.Util.Debug.code_at_node(zipper) ==
             "@foo_key Application.compile_env!(:my_app, :key)"
  end
end
