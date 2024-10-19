defmodule Igniter.Code.List do
  @moduledoc """
  Utilities for working with lists.
  """

  require Igniter.Code.Common
  alias Igniter.Code.Common
  alias Sourceror.Zipper

  @type equality_pred :: (Zipper.t(), Macro.t() -> boolean)

  @doc "Returns true if the `zipper` is at a list literal"
  @spec list?(Zipper.t()) :: boolean()
  def list?(zipper) do
    Common.node_matches_pattern?(zipper, value when is_list(value))
  end

  @doc "Prepends `quoted` to the list unless it is already present, determined by `equality_pred`."
  @spec prepend_new_to_list(Zipper.t(), quoted :: Macro.t(), equality_pred) ::
          {:ok, Zipper.t()} | :error
  def prepend_new_to_list(zipper, quoted, equality_pred \\ &Common.nodes_equal?/2) do
    Common.within(zipper, fn zipper ->
      if list?(zipper) do
        zipper
        |> find_list_item_index(fn value ->
          equality_pred.(value, quoted)
        end)
        |> case do
          nil ->
            prepend_to_list(zipper, quoted)

          _ ->
            {:ok, zipper}
        end
      else
        :error
      end
    end)
  end

  @doc "Appends `quoted` to the list unless it is already present, determined by `equality_pred`."
  @spec append_new_to_list(Zipper.t(), quoted :: Macro.t(), equality_pred) ::
          {:ok, Zipper.t()} | :error
  def append_new_to_list(zipper, quoted, equality_pred \\ &Common.nodes_equal?/2) do
    if list?(zipper) do
      zipper
      |> find_list_item_index(fn value ->
        equality_pred.(value, quoted)
      end)
      |> case do
        nil ->
          append_to_list(zipper, quoted)

        _ ->
          {:ok, zipper}
      end
    else
      :error
    end
  end

  @doc "Prepends `quoted` to the list"
  @spec prepend_to_list(Zipper.t(), quoted :: Macro.t()) :: {:ok, Zipper.t()} | :error
  def prepend_to_list(zipper, quoted) do
    if list?(zipper) do
      {:ok,
       zipper
       |> Common.maybe_move_to_single_child_block()
       |> Zipper.insert_child(quoted)}
    else
      :error
    end
  end

  @doc "Appends `quoted` to the list"
  @spec append_to_list(Zipper.t(), quoted :: Macro.t()) :: {:ok, Zipper.t()} | :error
  def append_to_list(zipper, quoted) do
    if list?(zipper) do
      {:ok,
       zipper
       |> Common.maybe_move_to_single_child_block()
       |> Zipper.append_child(quoted)}
    else
      :error
    end
  end

  @spec remove_from_list(Zipper.t(), predicate :: (Zipper.t() -> boolean())) ::
          {:ok, Zipper.t()} | :error
  def remove_from_list(zipper, predicate) do
    if list?(zipper) do
      Common.within(zipper, fn zipper ->
        zipper
        |> Zipper.down()
        |> Common.move_right(predicate)
        |> case do
          :error ->
            :error

          {:ok, zipper} ->
            {:ok, Zipper.remove(zipper)}
        end
      end)
      |> case do
        :error ->
          {:ok, zipper}

        {:ok, zipper} ->
          remove_from_list(zipper, predicate)
      end
    else
      :error
    end
  end

  @spec replace_in_list(Zipper.t(), predicate :: (Zipper.t() -> boolean()), term :: any()) ::
          {:ok, Zipper.t()} | :error
  def replace_in_list(zipper, predicate, value) do
    if list?(zipper) do
      Common.within(zipper, fn zipper ->
        zipper
        |> Zipper.down()
        |> Common.move_right(predicate)
        |> case do
          :error ->
            :error

          {:ok, zipper} ->
            {:ok, Igniter.Code.Common.replace_code(zipper, value)}
        end
      end)
      |> case do
        :error ->
          {:ok, zipper}

        {:ok, zipper} ->
          replace_in_list(zipper, predicate, value)
      end
    else
      :error
    end
  end

  @doc "Removes the item at the given index, returning `:error` if nothing is at that index"
  @spec remove_index(Zipper.t(), index :: non_neg_integer()) :: {:ok, Zipper.t()} | :error
  def remove_index(zipper, index) do
    if list?(zipper) do
      Common.within(zipper, fn zipper ->
        zipper
        |> Igniter.Code.Common.maybe_move_to_single_child_block()
        |> Zipper.down()
        |> Common.nth_right(index)
        |> case do
          :error ->
            :error

          {:ok, zipper} ->
            {:ok, Zipper.remove(zipper)}
        end
      end)
    else
      :error
    end
  end

  @doc "Finds the index of the first list item that satisfies `pred`"
  @spec find_list_item_index(Zipper.t(), (Zipper.t() -> boolean())) :: integer() | nil
  def find_list_item_index(zipper, pred) do
    # go into first list item
    zipper
    |> Common.maybe_move_to_single_child_block()
    |> Zipper.down()
    |> case do
      nil ->
        nil

      zipper ->
        find_index_right(zipper, pred, 0)
    end
  end

  @doc "Moves to the list item matching the given predicate"
  @spec move_to_list_item(Zipper.t(), (Zipper.t() -> boolean())) :: {:ok, Zipper.t()} | :error
  def move_to_list_item(zipper, pred) do
    # go into first list item
    zipper
    |> Common.maybe_move_to_single_child_block()
    |> Zipper.down()
    |> case do
      nil ->
        :error

      zipper ->
        do_move_to_list_item(zipper, pred)
    end
  end

  @doc "Moves to the list item matching the given predicate"
  @spec map(Zipper.t(), (Zipper.t() -> {:ok, Zipper.t()})) :: {:ok, Zipper.t()} | :error
  def map(zipper, fun) do
    # go into first list item
    zipper
    |> Common.maybe_move_to_single_child_block()
    |> Zipper.down()
    |> case do
      nil ->
        :error

      zipper ->
        do_map(zipper, fun)
    end
  end

  defp do_map(zipper, fun) do
    case Igniter.Code.Common.within(zipper, fun) do
      {:ok, zipper} ->
        case Zipper.right(zipper) do
          nil ->
            {:ok, zipper}

          right ->
            do_map(right, fun)
        end

      :error ->
        :error
    end
  end

  @doc "Moves to the list item matching the given predicate, assuming you are currently inside the list"
  def do_move_to_list_item(zipper, pred) do
    if pred.(zipper) do
      {:ok, zipper}
    else
      zipper
      |> Zipper.right()
      |> case do
        nil ->
          :error

        right ->
          do_move_to_list_item(right, pred)
      end
    end
  end

  defp find_index_right(zipper, pred, index) do
    if pred.(Common.maybe_move_to_single_child_block(zipper)) do
      index
    else
      case Zipper.right(zipper) do
        nil ->
          nil

        zipper ->
          zipper
          |> find_index_right(pred, index + 1)
      end
    end
  end
end
