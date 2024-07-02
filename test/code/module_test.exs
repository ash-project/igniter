defmodule Igniter.Code.ModuleTest do
  use ExUnit.Case

  doctest Igniter.Code.Module

  test "modules will be moved according to config" do
    %{rewrite: rewrite} =
      Igniter.new()
      |> Igniter.assign(:igniter_exs,
        module_location: :inside_matching_folder
      )
      |> Igniter.include_or_create_elixir_file("lib/foo/bar.ex", "defmodule Foo.Bar do\nend")
      |> Igniter.include_or_create_elixir_file(
        "lib/foo/bar/baz.ex",
        "defmodule Foo.Bar.Baz do\nend"
      )
      |> Igniter.prepare_for_write()

    paths = Rewrite.paths(rewrite)

    assert "lib/foo/bar/bar.ex" in paths
    assert "lib/foo/bar/baz.ex" in paths
  end

  test "modules can be found anywhere across the project" do
    %{rewrite: rewrite} =
      Igniter.new()
      |> Igniter.create_new_elixir_file("lib/foo/bar.ex", """
        defmodule Foo.Bar do
          defmodule Baz do
            10
          end
        end
      """)
      |> Igniter.Code.Module.find_and_update_or_create_module(
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
      |> Igniter.create_new_elixir_file("lib/foo/bar.ex", """
      defmodule Foo.Bar do
      end
      """)
      |> Igniter.Code.Module.find_and_update_or_create_module(
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
      |> Igniter.create_new_elixir_file("lib/foo/bar/something.ex", """
      defmodule Foo.Bar.Something do
      end
      """)
      |> Igniter.Code.Module.find_and_update_or_create_module(
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
end
