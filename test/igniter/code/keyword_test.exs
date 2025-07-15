defmodule Igniter.Code.KeywordTest do
  use ExUnit.Case

  test "remove_keyword_key removes the key" do
    assert "[a: 1]" ==
             "[a: 1, b: 1]"
             |> Sourceror.parse_string!()
             |> Sourceror.Zipper.zip()
             |> Igniter.Code.Keyword.remove_keyword_key(:b)
             |> elem(1)
             |> Map.get(:node)
             |> Sourceror.to_string()
  end

  test "remove_keyword_key removes from a call, not adding brackets" do
    assert "foo(a: 1)" ==
             "foo(a: 1, b: 1)"
             |> Sourceror.parse_string!()
             |> Sourceror.Zipper.zip()
             |> Sourceror.Zipper.down()
             |> Igniter.Code.Keyword.remove_keyword_key(:b)
             |> elem(1)
             |> Sourceror.Zipper.topmost_root()
             |> Sourceror.to_string()
  end

  test "remove_keyword_key removes from the second argument" do
    assert "foo(bar, a: 1)" ==
             "foo bar, a: 1, b: 1"
             |> Sourceror.parse_string!()
             |> Sourceror.Zipper.zip()
             |> Igniter.Code.Function.move_to_nth_argument(1)
             |> elem(1)
             |> Igniter.Code.Keyword.remove_keyword_key(:b)
             |> elem(1)
             |> Sourceror.Zipper.topmost_root()
             |> Sourceror.to_string()
  end

  test "set_keyword_key passes through errors from updater" do
    zipper =
      "[a: 1]"
      |> Sourceror.parse_string!()
      |> Sourceror.Zipper.zip()

    assert {:error, "test error"} ==
             Igniter.Code.Keyword.set_keyword_key(zipper, :a, 2, fn _ ->
               {:error, "test error"}
             end)
  end

  test "set_keyword_key passes through warnings from updater" do
    zipper =
      "[a: 1]"
      |> Sourceror.parse_string!()
      |> Sourceror.Zipper.zip()

    assert {:warning, "test warning"} ==
             Igniter.Code.Keyword.set_keyword_key(zipper, :a, 2, fn _ ->
               {:warning, "test warning"}
             end)
  end

  test "put_in_keyword passes through errors from updater" do
    zipper =
      "[a: [b: 1]]"
      |> Sourceror.parse_string!()
      |> Sourceror.Zipper.zip()

    assert {:error, "test error"} ==
             Igniter.Code.Keyword.put_in_keyword(zipper, [:a, :b], 2, fn _ ->
               {:error, "test error"}
             end)
  end

  test "put_in_keyword passes through warnings from updater" do
    zipper =
      "[a: [b: 1]]"
      |> Sourceror.parse_string!()
      |> Sourceror.Zipper.zip()

    assert {:warning, "test warning"} ==
             Igniter.Code.Keyword.put_in_keyword(zipper, [:a, :b], 2, fn _ ->
               {:warning, "test warning"}
             end)
  end
end
