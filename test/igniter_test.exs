defmodule IgniterTest do
  use ExUnit.Case
  doctest Igniter

  test "greets the world" do
    assert Igniter.hello() == :world
  end
end
