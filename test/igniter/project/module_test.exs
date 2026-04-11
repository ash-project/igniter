# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Igniter.Project.ModuleTest do
  use ExUnit.Case
  import Igniter.Test

  test "module_name_prefix/1" do
    assert Igniter.Project.Module.module_name_prefix(test_project()) == Test
  end

  describe "find_module/2 strategy cascade" do
    defp find_module_log(igniter) do
      get_in(igniter.assigns, [:private, :find_module_log]) || []
    end

    test "finds a module at its conventional path" do
      igniter =
        test_project()
        |> Igniter.create_new_file("lib/test/foo.ex", """
        defmodule Test.Foo do
          @moduledoc false
        end
        """)

      {:ok, {igniter, _source, _zipper}} =
        Igniter.Project.Module.find_module(igniter, Test.Foo)

      assert {Test.Foo, :conventional_path} in find_module_log(igniter)
    end

    test "second lookup hits the module index cache" do
      igniter =
        test_project()
        |> Igniter.create_new_file("lib/test/foo.ex", """
        defmodule Test.Foo do
          @moduledoc false
        end
        """)

      {:ok, {igniter, _source, _zipper}} =
        Igniter.Project.Module.find_module(igniter, Test.Foo)

      {:ok, {igniter, _source, _zipper}} =
        Igniter.Project.Module.find_module(igniter, Test.Foo)

      log = find_module_log(igniter)
      assert log == [{Test.Foo, :conventional_path}, {Test.Foo, :module_index}]
    end

    test "create_module warms the cache so find_module hits the index" do
      igniter =
        test_project()
        |> Igniter.Project.Module.create_module(Test.Bar, """
          @moduledoc false
        """)

      {:ok, {igniter, _source, _zipper}} =
        Igniter.Project.Module.find_module(igniter, Test.Bar)

      assert find_module_log(igniter) == [{Test.Bar, :module_index}]
    end

    test "finds a module by filename match when not at conventional path" do
      igniter =
        test_project()
        |> Igniter.create_new_file("lib/somewhere/unexpected/baz.ex", """
        defmodule Test.Baz do
          @moduledoc false
        end
        """)

      {:ok, {igniter, _source, _zipper}} =
        Igniter.Project.Module.find_module(igniter, Test.Baz)

      assert {Test.Baz, :filename_match} in find_module_log(igniter)
    end

    test "finds a module by directory search when filename doesn't match" do
      # Module Test.Custom.Thing in a file whose basename isn't "thing.ex"
      # but lives under a directory matching a parent segment
      igniter =
        test_project()
        |> Igniter.create_new_file("lib/custom/models.ex", """
        defmodule Test.Custom.Thing do
          @moduledoc false
        end
        """)

      {:ok, {igniter, _source, _zipper}} =
        Igniter.Project.Module.find_module(igniter, Test.Custom.Thing)

      assert {Test.Custom.Thing, :directory_search} in find_module_log(igniter)
    end

    test "falls back to full scan when no heuristic matches" do
      # Module in a file where neither the filename nor directory segments help
      igniter =
        test_project()
        |> Igniter.create_new_file("lib/grab_bag.ex", """
        defmodule Test.Hidden.Treasure do
          @moduledoc false
        end
        """)

      {:ok, {igniter, _source, _zipper}} =
        Igniter.Project.Module.find_module(igniter, Test.Hidden.Treasure)

      assert {Test.Hidden.Treasure, :full_scan} in find_module_log(igniter)
    end

    test "cache is updated after each strategy so subsequent lookups are instant" do
      igniter =
        test_project()
        |> Igniter.create_new_file("lib/grab_bag.ex", """
        defmodule Test.Hidden.Treasure do
          @moduledoc false
        end
        """)

      # First lookup: full scan
      {:ok, {igniter, _source, _zipper}} =
        Igniter.Project.Module.find_module(igniter, Test.Hidden.Treasure)

      # Second lookup: cache hit
      {:ok, {igniter, _source, _zipper}} =
        Igniter.Project.Module.find_module(igniter, Test.Hidden.Treasure)

      log = find_module_log(igniter)
      assert log == [{Test.Hidden.Treasure, :full_scan}, {Test.Hidden.Treasure, :module_index}]
    end

    test "multiple different modules each record their own strategy" do
      igniter =
        test_project()
        |> Igniter.Project.Module.create_module(Test.Alpha, "@moduledoc false")
        |> Igniter.create_new_file("lib/test/beta.ex", """
        defmodule Test.Beta do
          @moduledoc false
        end
        """)

      # Alpha was created via create_module, so cache is warm
      {:ok, {igniter, _, _}} = Igniter.Project.Module.find_module(igniter, Test.Alpha)
      # Beta is at its conventional path
      {:ok, {igniter, _, _}} = Igniter.Project.Module.find_module(igniter, Test.Beta)

      log = find_module_log(igniter)
      assert {Test.Alpha, :module_index} in log
      assert {Test.Beta, :conventional_path} in log
    end

    test "returns error when module does not exist" do
      igniter = test_project()

      assert {:error, _igniter} =
               Igniter.Project.Module.find_module(igniter, Test.DoesNotExist)
    end

    test "finds module inside_matching_folder convention" do
      igniter =
        test_project()
        |> Igniter.create_new_file("lib/test/widget/widget.ex", """
        defmodule Test.Widget do
          @moduledoc false
        end
        """)

      {:ok, {igniter, _source, _zipper}} =
        Igniter.Project.Module.find_module(igniter, Test.Widget)

      assert {Test.Widget, :conventional_path} in find_module_log(igniter)
    end
  end
end
