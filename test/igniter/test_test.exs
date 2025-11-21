# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule Igniter.TestTest do
  use ExUnit.Case
  import Igniter.Test

  describe "refute_creates/2" do
    test "passes when file is not created" do
      test_project()
      |> refute_creates("lib/non_existent_file.ex")
    end

    test "passes when file already exists (not created in this run)" do
      test_project()
      |> refute_creates("mix.exs")
    end

    test "fails when file is created" do
      assert_raise ExUnit.AssertionError,
                   ~r/Expected "lib\/new_file\.ex" to not have been created, but it was/,
                   fn ->
                     test_project()
                     |> Igniter.create_new_file("lib/new_file.ex", "content")
                     |> refute_creates("lib/new_file.ex")
                   end
    end

    test "returns the igniter unchanged on success" do
      igniter =
        test_project()
        |> Igniter.create_new_file("lib/some_file.ex", "content")

      result = refute_creates(igniter, "lib/non_existent_file.ex")
      assert result == igniter
    end
  end

  describe "assert_creates/3" do
    test "passes when file is created" do
      test_project()
      |> Igniter.create_new_file("lib/new_file.ex", "content")
      |> assert_creates("lib/new_file.ex", "content\n")
    end

    test "passes when file is created without content validation" do
      test_project()
      |> Igniter.create_new_file("lib/new_file.ex", "content")
      |> assert_creates("lib/new_file.ex")
    end

    test "fails when file is not created" do
      assert_raise ExUnit.AssertionError,
                   ~r/Expected "lib\/non_existent\.ex" to have been created, but it was not/,
                   fn ->
                     test_project()
                     |> assert_creates("lib/non_existent.ex")
                   end
    end

    test "fails when file already existed" do
      assert_raise ExUnit.AssertionError,
                   ~r/Expected "mix\.exs" to have been created, but it already existed/,
                   fn ->
                     test_project()
                     |> assert_creates("mix.exs")
                   end
    end

    test "fails when content doesn't match" do
      assert_raise ExUnit.AssertionError,
                   ~r/Expected created file "lib\/new_file\.ex" to have the following contents/,
                   fn ->
                     test_project()
                     |> Igniter.create_new_file("lib/new_file.ex", "actual content")
                     |> assert_creates("lib/new_file.ex", "expected content\n")
                   end
    end
  end

  describe "assert_moves/3" do
    test "passes when file is moved" do
      test_project(files: %{"old.exs" => "content"})
      |> Igniter.move_file("old.exs", "new.exs")
      |> assert_moves("old.exs", "new.exs")
    end

    test "fails when file is not moved" do
      assert_raise ExUnit.AssertionError,
                   ~r/Expected \"old.exs\" to have been moved, but it was not.\n\n     No files were moved./,
                   fn ->
                     test_project(files: %{"old.exs" => "content"})
                     |> assert_moves("old.exs", "new.exs")
                   end
    end

    test "fails when different file is moved" do
      assert_raise ExUnit.AssertionError,
                   ~r/Expected \"one.exs\" to have been moved, but it was not.\n\n     The following files were moved:\n\n     \* two.exs\n         ↳ three.exs/,
                   fn ->
                     test_project(files: %{"one.exs" => "content", "two.exs" => "content"})
                     |> Igniter.move_file("two.exs", "three.exs")
                     |> assert_moves("one.exs", "three.exs")
                   end
    end

    test "fails when file is not moved to a different location" do
      assert_raise ExUnit.AssertionError,
                   ~r/Expected \"old.exs\" to have been moved to:\n\n         new.exs\n\n     But it was moved to:\n\n         mature.exs/,
                   fn ->
                     test_project(files: %{"old.exs" => "content"})
                     |> Igniter.move_file("old.exs", "mature.exs")
                     |> assert_moves("old.exs", "new.exs")
                   end
    end
  end
end
