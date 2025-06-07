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
end
