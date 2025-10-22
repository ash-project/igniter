# SPDX-FileCopyrightText: 2025 igniter contributors <https://github.com/ash-project/igniter/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule Igniter.Code.ListTest do
  alias Igniter.Code
  alias Sourceror.Zipper

  use ExUnit.Case
  doctest Igniter.Code.List

  describe "map/2" do
    test "applies the function to every element in the list" do
      {:ok, zipper} =
        "[1, 2, 3, 4]"
        |> Code.Common.parse_to_zipper!()
        |> Code.List.map(fn %Zipper{node: {:__block__, meta, [n]}} = zipper ->
          updated_node = {:__block__, meta, [n * 2]}
          {:ok, %Zipper{zipper | node: updated_node}}
        end)

      assert {:ok, [2, 4, 6, 8]} ==
               zipper |> Zipper.up() |> Code.Common.expand_literal()
    end

    test "the returned zipper points to the final element" do
      {:ok, zipper} =
        "[1, 2, 3, 4]"
        |> Code.Common.parse_to_zipper!()
        |> Code.List.map(fn %Zipper{node: {:__block__, meta, [n]}} = zipper ->
          updated_node = {:__block__, meta, [n * 2]}
          {:ok, %Zipper{zipper | node: updated_node}}
        end)

      assert {:ok, 8} == Code.Common.expand_literal(zipper)
    end
  end
end
