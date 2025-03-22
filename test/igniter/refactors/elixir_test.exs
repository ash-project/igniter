defmodule Igniter.Refactors.ElixirTest do
  use ExUnit.Case
  import Igniter.Test

  test "rewrites unless as an if with negated condition" do
    bad = "unless x, do: y"

    good = "if !x, do: y"

    assert_format(bad, good)

    bad = """
    unless x do
      y
    else
      z
    end
    """

    good = """
    if !x do
      y
    else
      z
    end
    """

    assert_format(bad, good)
  end

  test "rewrites pipelines with negated condition" do
    bad = "x |> unless(do: y)"

    good = "!x |> if(do: y)"

    assert_format(bad, good)

    bad = "x |> foo() |> unless(do: y)"

    good = "x |> foo() |> Kernel.!() |> if(do: y)"

    assert_format(bad, good)

    bad = "unless x |> foo(), do: y"

    good = """
    if !(x |> foo()),
      do: y
    """

    assert_format(bad, good)
  end

  test "rewrites in as not in" do
    assert_format("unless x in y, do: 1", "if x not in y, do: 1")
  end

  @tag :focus
  test "rewrites equality operators" do
    assert_format("unless x == y, do: 1", "if x != y, do: 1")
    assert_format("unless x === y, do: 1", "if x !== y, do: 1")
    assert_format("unless x != y, do: 1", "if x == y, do: 1")
    assert_format("unless x !== y, do: 1", "if x === y, do: 1")
  end

  test "rewrites boolean or is_* conditions with not" do
    assert_format("unless x > 0, do: 1", "if not (x > 0), do: 1")

    assert_format(
      "unless is_atom(x), do: 1",
      """
      if not is_atom(x),
        do: 1
      """
    )
  end

  test "removes ! or not in condition" do
    assert_format("unless not x, do: 1", "if x, do: 1")
    assert_format("unless !x, do: 1", "if x, do: 1")
  end

  defp assert_format(code, expectation) do
    test_project()
    |> Igniter.create_new_file("lib/example.ex", """
    defmodule Example do
      #{code}
    end
    """)
    |> Igniter.Refactors.Elixir.unless_to_if_not()
    |> assert_creates("lib/example.ex", """
    defmodule Example do
    #{indent(expectation)}
    end
    """)
  end

  defp indent(string) do
    string
    |> String.split("\n", trim: true)
    |> Enum.map_join("\n", &"  #{&1}")
  end
end
