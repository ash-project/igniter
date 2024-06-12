defmodule Igniter.Code.Function do
  @moduledoc """
  Utilities for working with functions.
  """

  alias Igniter.Code.Common
  alias Sourceror.Zipper

  @doc "Returns `true` if the argument at the provided index exists and matches the provided pattern"
  defmacro argument_matches_pattern?(zipper, index, pattern) do
    quote do
      Igniter.Code.Function.argument_matches_predicate?(
        unquote(zipper),
        unquote(index),
        fn zipper ->
          code_at_node =
            zipper
            |> Sourceror.Zipper.subtree()
            |> Sourceror.Zipper.root()

          match?(unquote(pattern), code_at_node)
        end
      )
    end
  end

  @doc "Moves to a function call by the given name and arity, matching the given predicate, in the current scope"
  @spec move_to_function_call_in_current_scope(Zipper.t(), atom, non_neg_integer()) ::
          {:ok, Zipper.t()} | :error
  def move_to_function_call_in_current_scope(zipper, name, arity, predicate \\ fn _ -> true end)

  def move_to_function_call_in_current_scope(zipper, name, [arity | arities], predicate)
      when is_list(arities) do
    case move_to_function_call_in_current_scope(zipper, name, arity, predicate) do
      :error ->
        move_to_function_call_in_current_scope(zipper, name, arities, predicate)

      {:ok, zipper} ->
        {:ok, zipper}
    end
  end

  def move_to_function_call_in_current_scope(_, _, [], _) do
    :error
  end

  def move_to_function_call_in_current_scope(%Zipper{} = zipper, name, arity, predicate) do
    zipper
    |> Common.maybe_move_to_block()
    |> Common.move_right(fn zipper ->
      function_call?(zipper, name, arity) && predicate.(zipper)
    end)
  end

  @doc "Returns `true` if the node is a function call of the given name and arity"
  @spec function_call?(Zipper.t(), atom, non_neg_integer()) :: boolean()
  def function_call?(%Zipper{} = zipper, name, arity) do
    zipper
    |> Common.maybe_move_to_block()
    |> Zipper.subtree()
    |> Zipper.root()
    |> case do
      {^name, _, args} ->
        Enum.count(args) == arity

      {{^name, _, context}, _, args} when is_atom(context) ->
        Enum.count(args) == arity

      {:|>, _, [{^name, _, context} | rest]} when is_atom(context) ->
        Enum.count(rest) == arity - 1

      {:|>, _, [^name | rest]} ->
        Enum.count(rest) == arity - 1

      _ ->
        false
    end
  end

  @doc "Returns `true` if the ndoe is a function call of the given name"
  @spec function_call?(Zipper.t(), atom) :: boolean()
  def function_call?(%Zipper{} = zipper, name) do
    zipper
    |> Common.maybe_move_to_block()
    |> Zipper.subtree()
    |> Zipper.root()
    |> case do
      {^name, _, _} ->
        true

      {{^name, _, context}, _, _} when is_atom(context) ->
        true

      {:|>, _, [{^name, _, context} | _rest]} when is_atom(context) ->
        true

      {:|>, _, [^name | _rest]} ->
        true

      _ ->
        false
    end
  end

  @doc "Returns `true` if the ndoe is a function call"
  @spec function_call?(Zipper.t()) :: boolean()
  def function_call?(%Zipper{} = zipper) do
    zipper
    |> Common.maybe_move_to_block()
    |> Zipper.subtree()
    |> Zipper.root()
    |> case do
      {:|>, _, [{name, _, context} | _rest]} when is_atom(context) and is_atom(name) ->
        true

      {:|>, _, [name | _rest]} when is_atom(name) ->
        true

      {name, _, _} when is_atom(name) ->
        true

      {{name, _, context}, _, _} when is_atom(context) and is_atom(name) ->
        true

      _ ->
        false
    end
  end

  def update_nth_argument(zipper, index, func) do
    if pipeline?(zipper) do
      if index == 0 do
        zipper
        |> Zipper.down()
        |> case do
          nil ->
            :error

          zipper ->
            func.(zipper)
        end
      else
        zipper
        |> Zipper.down()
        |> case do
          nil ->
            :error

          zipper ->
            zipper
            |> Zipper.rightmost()
            |> Zipper.down()
            |> case do
              nil ->
                :error

              zipper ->
                zipper
                |> Common.nth_right(index)
                |> case do
                  :error ->
                    :error

                  {:ok, nth} ->
                    func.(nth)
                end
            end
        end
      end
    else
      zipper
      |> Zipper.down()
      |> case do
        nil ->
          :error

        zipper ->
          zipper
          |> Common.nth_right(index)
          |> case do
            :error ->
              :error

            {:ok, nth} ->
              func.(nth)
          end
      end
    end
  end

  def move_to_nth_argument(zipper, index) do
    if pipeline?(zipper) do
      if index == 0 do
        zipper
        |> Zipper.down()
        |> case do
          nil ->
            :error

          zipper ->
            {:ok, zipper}
        end
      else
        zipper
        |> Zipper.down()
        |> case do
          nil ->
            :error

          zipper ->
            zipper
            |> Zipper.rightmost()
            |> Zipper.down()
            |> case do
              nil ->
                :error

              zipper ->
                zipper
                |> Common.nth_right(index)
                |> case do
                  :error ->
                    :error

                  {:ok, nth} ->
                    {:ok, nth}
                end
            end
        end
      end
    else
      zipper
      |> Zipper.down()
      |> case do
        nil ->
          :error

        zipper ->
          zipper
          |> Common.nth_right(index)
          |> case do
            :error ->
              :error

            {:ok, nth} ->
              {:ok, nth}
          end
      end
    end
  end

  def append_argument(zipper, value) do
    zipper
    |> Zipper.append_child(value)
  end

  def argument_matches_predicate?(zipper, index, func) do
    if pipeline?(zipper) do
      if index == 0 do
        zipper
        |> Zipper.down()
        |> case do
          nil -> nil
          zipper -> func.(zipper)
        end
      else
        zipper
        |> Zipper.down()
        |> case do
          nil ->
            nil

          zipper ->
            zipper
            |> Zipper.rightmost()
            |> Zipper.down()
            |> case do
              nil ->
                nil

              zipper ->
                zipper
                |> Common.nth_right(index - 1)
                |> case do
                  :error ->
                    false

                  {:ok, zipper} ->
                    zipper
                    |> Common.maybe_move_to_block()
                    |> func.()
                end
            end
        end
      end
    else
      zipper
      |> Zipper.down()
      |> case do
        nil ->
          false

        zipper ->
          zipper
          |> Common.nth_right(index)
          |> case do
            :error ->
              false

            {:ok, zipper} ->
              zipper
              |> Common.maybe_move_to_block()
              |> func.()
          end
      end
    end
  end

  def pipeline?(zipper) do
    zipper
    |> Zipper.subtree()
    |> Zipper.root()
    |> case do
      {:|>, _, _} -> true
      _ -> false
    end
  end
end
