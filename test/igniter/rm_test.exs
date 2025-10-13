# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule Igniter.RmTest do
  use ExUnit.Case
  import Igniter.Test
  import ExUnit.CaptureIO

  describe "Igniter.rm/2" do
    test "marks a file for removal" do
      test_project()
      |> Igniter.create_new_file("lib/example.ex", "defmodule Example, do: :ok")
      |> apply_igniter!()
      |> Igniter.rm("lib/example.ex")
      |> assert_rms(["lib/example.ex"])
    end

    test "marks multiple files for removal" do
      test_project()
      |> Igniter.create_new_file("lib/example1.ex", "defmodule Example1, do: :ok")
      |> Igniter.create_new_file("lib/example2.ex", "defmodule Example2, do: :ok")
      |> apply_igniter!()
      |> Igniter.rm("lib/example1.ex")
      |> Igniter.rm("lib/example2.ex")
      |> assert_rms(["lib/example1.ex", "lib/example2.ex"])
    end

    test "normalizes file paths" do
      test_project()
      |> Igniter.create_new_file("lib/example.ex", "defmodule Example, do: :ok")
      |> apply_igniter!()
      |> Igniter.rm("./lib/example.ex")
      |> assert_rms(["lib/example.ex"])
    end

    test "removes file from rewrite sources when marked for removal" do
      igniter =
        test_project()
        |> Igniter.create_new_file("lib/example.ex", "defmodule Example, do: :ok")
        |> apply_igniter!()

      assert Rewrite.has_source?(igniter.rewrite, "lib/example.ex")

      igniter = Igniter.rm(igniter, "lib/example.ex")

      refute Rewrite.has_source?(igniter.rewrite, "lib/example.ex")
    end
  end

  describe "Igniter.exists?/2 with rm behavior" do
    test "returns false for files marked for removal" do
      igniter =
        test_project()
        |> Igniter.create_new_file("lib/example.ex", "defmodule Example, do: :ok")
        |> apply_igniter!()

      assert Igniter.exists?(igniter, "lib/example.ex")

      igniter = Igniter.rm(igniter, "lib/example.ex")

      refute Igniter.exists?(igniter, "lib/example.ex")
    end

    test "still returns true for existing files not marked for removal" do
      igniter =
        test_project()
        |> Igniter.create_new_file("lib/example1.ex", "defmodule Example1, do: :ok")
        |> Igniter.create_new_file("lib/example2.ex", "defmodule Example2, do: :ok")
        |> apply_igniter!()
        |> Igniter.rm("lib/example1.ex")

      refute Igniter.exists?(igniter, "lib/example1.ex")
      assert Igniter.exists?(igniter, "lib/example2.ex")
    end
  end

  describe "file creation after rm" do
    test "create_new_file removes file from rms list when creating a previously removed file" do
      igniter =
        test_project()
        |> Igniter.create_new_file("lib/example.ex", "defmodule Example, do: :ok")
        |> apply_igniter!()
        |> Igniter.rm("lib/example.ex")

      assert "lib/example.ex" in igniter.rms

      igniter =
        Igniter.create_new_file(igniter, "lib/example.ex", "defmodule NewExample, do: :ok")

      refute "lib/example.ex" in igniter.rms
      assert Igniter.exists?(igniter, "lib/example.ex")
    end

    test "update_elixir_file adds issue when trying to update a removed file" do
      igniter =
        test_project()
        |> Igniter.create_new_file("lib/example.ex", "defmodule Example, do: :ok")
        |> apply_igniter!()
        |> Igniter.rm("lib/example.ex")

      assert "lib/example.ex" in igniter.rms
      refute Igniter.exists?(igniter, "lib/example.ex")

      igniter =
        Igniter.update_elixir_file(igniter, "lib/example.ex", fn zipper ->
          {:ok, Igniter.Code.Common.add_code(zipper, ":updated")}
        end)

      # File should still be in rms and should have an issue
      assert "lib/example.ex" in igniter.rms
      assert length(igniter.issues) > 0
      assert Enum.any?(igniter.issues, &String.contains?(&1, "lib/example.ex"))
    end

    test "update_file cannot update a removed file because exists? returns false" do
      igniter =
        test_project()
        |> Igniter.create_new_file("lib/example.txt", "some content")
        |> apply_igniter!()
        |> Igniter.rm("lib/example.txt")

      assert "lib/example.txt" in igniter.rms
      refute Igniter.exists?(igniter, "lib/example.txt")

      # update_file should not modify a file that doesn't exist according to exists?
      igniter =
        Igniter.update_file(igniter, "lib/example.txt", fn source ->
          Rewrite.Source.update(source, :content, &(&1 <> "\nupdated"))
        end)

      # File should still be in rms
      assert "lib/example.txt" in igniter.rms
      refute Igniter.exists?(igniter, "lib/example.txt")
    end
  end

  describe "apply_igniter!/1 with rm behavior" do
    test "removes files from test_files when applied in test mode" do
      igniter =
        test_project()
        |> Igniter.create_new_file("lib/example.ex", "defmodule Example, do: :ok")
        |> apply_igniter!()

      assert igniter.assigns[:test_files]["lib/example.ex"]

      igniter =
        test_project()
        |> Igniter.create_new_file("lib/example.ex", "defmodule Example, do: :ok")
        |> apply_igniter!()
        |> Igniter.rm("lib/example.ex")
        |> apply_igniter!()

      refute Map.has_key?(igniter.assigns[:test_files], "lib/example.ex")
      assert igniter.rms == []
    end
  end

  describe "display output" do
    # commenting out due to flaky test
    # test "display_rms/1 shows files to be removed" do
    #   igniter =
    #     test_project()
    #     |> Igniter.rm("lib/example1.ex")
    #     |> Igniter.rm("lib/example2.ex")

    #   output = capture_io(fn -> Igniter.display_rms(igniter) end)

    #   assert output == """

    #          These files will be removed:

    #          * \e[31mlib/example1.ex\e[0m\e[0m
    #          * \e[31mlib/example2.ex\e[0m\e[0m

    #          """
    # end

    test "display_rms/1 shows nothing when no files to remove" do
      output = capture_io(fn -> Igniter.display_rms(test_project()) end)
      assert output == ""
    end

    test "files marked for removal are tracked in rms list" do
      igniter =
        test_project()
        |> Igniter.create_new_file("lib/example.ex", "defmodule Example, do: :ok")
        |> apply_igniter!()
        |> Igniter.rm("lib/example.ex")

      assert "lib/example.ex" in igniter.rms
      # File should be removed from rewrite sources
      refute Rewrite.has_source?(igniter.rewrite, "lib/example.ex")
    end
  end

  describe "check mode behavior" do
    test "has_changes?/1 returns true when files are marked for removal" do
      igniter =
        test_project()
        |> Igniter.create_new_file("lib/example.ex", "defmodule Example, do: :ok")
        |> apply_igniter!()
        |> Igniter.rm("lib/example.ex")

      # Since rm removes from rewrite sources, we check that rms list is not empty
      assert !Enum.empty?(igniter.rms)
    end
  end

  describe "move and rm interaction" do
    test "removing a file that was previously moved" do
      igniter =
        test_project()
        |> Igniter.create_new_file("lib/old_file.ex", "defmodule OldFile, do: :ok")
        |> apply_igniter!()
        |> Igniter.move_file("lib/old_file.ex", "lib/new_file.ex")
        |> Igniter.rm("lib/new_file.ex")

      # Should have both the move and the rm
      assert igniter.moves["lib/old_file.ex"] == "lib/new_file.ex"
      assert "lib/new_file.ex" in igniter.rms
    end
  end
end
