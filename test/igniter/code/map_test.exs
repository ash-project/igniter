defmodule Igniter.Code.Map.Test do
  alias Igniter.Code
  alias Sourceror.Zipper

  use ExUnit.Case

  doctest Igniter.Code.Map

  describe "set_map_key/4" do
    test "inserts value into empty map" do
      {:ok, zipper} =
        "%{}"
        |> Code.Common.parse_to_zipper!()
        |> Code.Map.set_map_key(:foo, :bar, fn _valuex -> flunk() end)

      assert {:ok, %{foo: :bar}} == Code.Common.expand_literal(zipper)
    end

    test "inserts value into map if not present" do
      {:ok, zipper} =
        "%{hello: :world}"
        |> Code.Common.parse_to_zipper!()
        |> Code.Map.set_map_key(:foo, :bar, &flunk/1)

      assert {:ok, %{foo: :bar, hello: :world}} == Code.Common.expand_literal(zipper)
    end

    test "replaces keys in map with the updater rather than the passed value" do
      {:ok, zipper} =
        "%{hello: :world}"
        |> Code.Common.parse_to_zipper!()
        |> Code.Map.set_map_key(:hello, :this_value_is_ignored, fn %Zipper{node: :world} = zipper ->
          Zipper.replace(zipper, :baz)
        end)

      assert {:ok, %{hello: :baz}} == Code.Common.expand_literal(zipper)
    end
  end

  describe "put_in_map/4" do
    test "inserts value into empty map" do
      {:ok, zipper} =
        "%{}"
        |> Code.Common.parse_to_zipper!()
        |> Code.Map.put_in_map([:foo], :bar, fn _valuex -> flunk() end)

      assert {:ok, %{foo: :bar}} == Code.Common.expand_literal(zipper)
    end

    test "inserts value into empty map at nested position" do
      {:ok, zipper} =
        "%{}"
        |> Code.Common.parse_to_zipper!()
        |> Code.Map.put_in_map([:alpha, :beta, :gamma], :abc, fn _valuex -> flunk() end)

      assert {:ok, %{alpha: %{beta: %{gamma: :abc}}}} == Code.Common.expand_literal(zipper)
    end
  end
end
