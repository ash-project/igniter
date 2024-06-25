defmodule Igniter.Code.ModuleTest do
  use ExUnit.Case

  test "proper_location/1 returns idiomatic path" do
    assert "lib/my_app/hello.ex" = Igniter.Code.Module.proper_location(MyApp.Hello)
  end

  describe "proper_test_location/1" do
    test "returns a path with _test appended if the module name doesn't end with Test" do
      assert "test/my_app/hello_test.exs" = Igniter.Code.Module.proper_test_location(MyApp.Hello)
    end

    test "returns a path without appending _test if the module name already ends with Test" do
      assert "test/my_app/hello_test.exs" =
               Igniter.Code.Module.proper_test_location(MyApp.HelloTest)
    end
  end
end
