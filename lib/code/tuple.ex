defmodule Igniter.Code.Tuple do
  @moduledoc """
  Utilities for working with tuples.
  """
  alias Sourceror.Zipper
  alias Igniter.Code.Common

  @doc "Returns `true` if the zipper is at a literal tuple, `false` if not."
  @spec tuple?(Zipper.t()) :: boolean()
  def tuple?(item) do
    item
    |> Zipper.subtree()
    |> Zipper.root()
    |> case do
      {:{}, _, _} -> true
      {_, _} -> true
      _ -> false
    end
  end

  @doc "Returns a zipper at the tuple element at the given index, or `:error` if the index is out of bounds."
  @spec tuple_elem(Zipper.t(), elem :: non_neg_integer()) :: {:ok, Zipper.t()} | :error
  def tuple_elem(item, elem) do
    item
    |> Common.maybe_move_to_block()
    |> Zipper.down()
    |> Common.nth_right(elem)
    |> case do
      {:ok, nth} ->
        {:ok, Common.maybe_move_to_block(nth)}

      :error ->
        :error
    end
  end
end
