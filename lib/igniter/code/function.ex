defmodule Igniter.Code.Function do
  @moduledoc """
  Utilities for working with functions.
  """

  require Igniter.Code.Common
  alias Igniter.Code.Common
  alias Sourceror.Zipper

  @doc """
  Returns `true` if the argument at the provided index exists and matches the provided pattern

  Note: to check for argument equality, use `argument_equals?/3` instead.
  """
  defmacro argument_matches_pattern?(zipper, index, pattern) do
    quote do
      Igniter.Code.Function.argument_matches_predicate?(
        unquote(zipper),
        unquote(index),
        fn zipper ->
          match?(unquote(pattern), zipper.node)
        end
      )
    end
  end

  @spec move_to_defp(Zipper.t(), fun :: atom, arity :: integer | list(integer)) ::
          {:ok, Zipper.t()} | :error
  def move_to_defp(zipper, fun, arity) do
    do_move_to_def(zipper, fun, arity, :defp)
  end

  @spec move_to_def(Zipper.t(), fun :: atom, arity :: integer | list(integer)) ::
          {:ok, Zipper.t()} | :error
  def move_to_def(zipper, fun, arity) do
    do_move_to_def(zipper, fun, arity, :def)
  end

  defp do_move_to_def(zipper, fun, [arity], kind) do
    do_move_to_def(zipper, fun, arity, kind)
  end

  defp do_move_to_def(zipper, fun, [arity | rest], kind) do
    case do_move_to_def(zipper, fun, arity, kind) do
      {:ok, zipper} -> {:ok, zipper}
      :error -> do_move_to_def(zipper, fun, rest, kind)
    end
  end

  defp do_move_to_def(zipper, fun, arity, kind) do
    case Common.move_to_pattern(
           zipper,
           {^kind, _, [{^fun, _, args}, _]} when length(args) == arity
         ) do
      :error ->
        if arity == 0 do
          case Common.move_to_pattern(
                 zipper,
                 {^kind, _, [{^fun, _, context}, _]} when is_atom(context)
               ) do
            :error ->
              :error

            {:ok, zipper} ->
              Common.move_to_do_block(zipper)
          end
        else
          :error
        end

      {:ok, zipper} ->
        Common.move_to_do_block(zipper)
    end
  end

  @doc "Moves to a function call by the given name and arity, matching the given predicate, in the current scope"
  @spec move_to_function_call_in_current_scope(
          Zipper.t(),
          atom,
          non_neg_integer() | list(non_neg_integer())
        ) ::
          {:ok, Zipper.t()} | :error
  def move_to_function_call_in_current_scope(zipper, name, arity, predicate \\ fn _ -> true end)

  def move_to_function_call_in_current_scope(zipper, name, [arity | arities], predicate) do
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
    if function_call?(zipper, name, arity) && predicate.(zipper) do
      {:ok, zipper}
    else
      Common.move_right(zipper, fn zipper ->
        function_call?(zipper, name, arity) && predicate.(zipper)
      end)
    end
  end

  @doc "Moves to a function call by the given name and arity, matching the given predicate, in the current or lower scope"
  @spec move_to_function_call(Zipper.t(), atom | {atom, atom}, non_neg_integer()) ::
          {:ok, Zipper.t()} | :error
  def move_to_function_call(zipper, name, arity, predicate \\ fn _ -> true end)

  def move_to_function_call(zipper, name, [arity | arities], predicate) do
    case move_to_function_call(zipper, name, arity, predicate) do
      :error ->
        move_to_function_call(zipper, name, arities, predicate)

      {:ok, zipper} ->
        {:ok, zipper}
    end
  end

  def move_to_function_call(_, _, [], _) do
    :error
  end

  def move_to_function_call(%Zipper{} = zipper, name, arity, predicate) do
    if function_call?(zipper, name, arity) && predicate.(zipper) do
      {:ok, zipper}
    else
      Common.move_next(zipper, fn zipper ->
        function_call?(zipper, name, arity) && predicate.(zipper)
      end)
    end
  end

  @doc """
  Returns `true` if the node is a function call of the given name

  If an `atom` is provided, it only matches functions in the form of `function(name)`.

  If an `{module, atom}` is provided, it matches functions called on the given module,
  taking into account any imports or aliases.
  """
  @spec function_call?(Zipper.t(), atom | {module, atom}, arity :: integer | :any | list(integer)) ::
          boolean()
  def function_call?(zipper, name, arity \\ :any)

  def function_call?(%Zipper{} = zipper, name, arity) when is_atom(name) do
    zipper
    |> Common.maybe_move_to_single_child_block()
    |> Zipper.node()
    |> case do
      {^name, _, args} ->
        arity == :any || Enum.count(args) == arity

      {{^name, _, context}, _, args} when is_atom(context) ->
        arity == :any || Enum.count(args) == arity

      {:|>, _, [{^name, _, context} | rest]} when is_atom(context) ->
        arity == :any || Enum.count(rest) == arity - 1

      {:|>, _, [^name | rest]} ->
        arity == :any || Enum.count(rest) == arity - 1

      _ ->
        false
    end
  end

  def function_call?(%Zipper{} = zipper, {module, name}, arity) when is_atom(name) do
    node =
      zipper
      |> Common.maybe_move_to_single_child_block()
      |> Igniter.Code.Common.expand_aliases()
      |> Zipper.node()

    split = module |> Module.split() |> Enum.map(&String.to_atom/1)

    imported? =
      case Igniter.Code.Common.current_env(zipper) do
        {:ok, env} ->
          Enum.any?(env.functions ++ env.macros, fn {imported_module, funcs} ->
            imported_module == module &&
              Enum.any?(funcs, fn {imported_name, imported_arity} ->
                name == imported_name && (arity == :any || Enum.count(imported_arity) == arity)
              end)
          end)

        _ ->
          false
      end

    case node do
      {{:., _, [{:__aliases__, _, ^split}, ^name]}, _, args} ->
        arity == :any || Enum.count(args) == arity

      {{:., _, [{:__aliases__, _, ^split}, {^name, _, context}]}, _, args}
      when is_atom(context) ->
        arity == :any || Enum.count(args) == arity

      {:|>, _,
       [
         _,
         {{:., _, [{:__aliases__, _, ^split}, ^name]}, _, args}
       ]} ->
        arity == :any || Enum.count(args) == arity - 1

      {:|>, _,
       [
         _,
         {{:., _, [{:__aliases__, _, ^split}, {^name, _, context}]}, _, args}
       ]}
      when is_atom(context) ->
        arity == :any || Enum.count(args) == arity - 1

      {^name, _, args} when imported? ->
        arity == :any || Enum.count(args) == arity

      {{^name, _, context}, _, args} when is_atom(context) and imported? ->
        arity == :any || Enum.count(args) == arity

      {:|>, _, [{^name, _, context} | rest]} when is_atom(context) and imported? ->
        arity == :any || Enum.count(rest) == arity - 1

      {:|>, _, [^name | rest]} when imported? ->
        arity == :any || Enum.count(rest) == arity - 1

      _ ->
        false
    end
  end

  @doc "Gets the name of a local function call, or `:error` if the node is not a function call or it cannot be determined"
  def get_local_function_call_name(%Zipper{} = zipper) do
    zipper
    |> Common.maybe_move_to_single_child_block()
    |> Zipper.node()
    |> case do
      {:|>, _, [{name, _, context} | _rest]} when is_atom(context) and is_atom(name) ->
        {:ok, name}

      {:|>, _, [name | _rest]} when is_atom(name) ->
        {:ok, name}

      {name, _, _args} when is_atom(name) ->
        {:ok, name}

      {{name, _, context}, _, _args} when is_atom(context) and is_atom(name) ->
        {:ok, name}

      _ ->
        :error
    end
  end

  @doc "Returns `true` if the node is a function call"
  @spec function_call?(Zipper.t()) :: boolean()
  def function_call?(%Zipper{} = zipper) do
    zipper
    |> Common.maybe_move_to_single_child_block()
    |> Zipper.node()
    |> case do
      {:|>, _,
       [
         _,
         {{:., _, [_, name]}, _, _}
       ]}
      when is_atom(name) ->
        true

      {:|>, _,
       [
         _,
         {{:., _, [_, {name, _, context}]}, _, _args}
       ]}
      when is_atom(name) and is_atom(context) ->
        true

      {:|>, _, [{name, _, context} | _rest]} when is_atom(context) and is_atom(name) ->
        true

      {:|>, _, [name | _rest]} when is_atom(name) ->
        true

      {name, _, _} when is_atom(name) ->
        true

      {{name, _, context}, _, _} when is_atom(context) and is_atom(name) ->
        true

      {{:., _, [_, name]}, _, _} when is_atom(name) ->
        true

      {{:., _, [_, {name, _, context}]}, _, _}
      when is_atom(name) and is_atom(context) ->
        true

      _ ->
        false
    end
  end

  @doc "Updates the `nth` argument of a function call, leaving the zipper at the function call's node."
  @spec update_nth_argument(
          Zipper.t(),
          non_neg_integer(),
          (Zipper.t() ->
             {:ok, Zipper.t()} | :error)
        ) ::
          {:ok, Zipper.t()} | :error
  def update_nth_argument(zipper, index, func) do
    Common.within(zipper, fn zipper ->
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
    end)
  end

  @doc "Moves to the `nth` argument of a function call."
  @spec move_to_nth_argument(
          Zipper.t(),
          non_neg_integer()
        ) ::
          {:ok, Zipper.t()} | :error
  def move_to_nth_argument(zipper, index) do
    if function_call?(zipper) do
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
        offset =
          case zipper.node do
            {{:., _, _}, _, _args} ->
              1

            _ ->
              0
          end

        zipper
        |> Zipper.down()
        |> case do
          nil ->
            :error

          zipper ->
            zipper
            |> Common.nth_right(index + offset)
            |> case do
              :error ->
                :error

              {:ok, nth} ->
                {:ok, nth}
            end
        end
      end
    else
      :error
    end
  end

  @doc "Appends an argument to a function call, leaving the zipper at the function call's node."
  @spec append_argument(Zipper.t(), any()) :: {:ok, Zipper.t()} | :error
  def append_argument(zipper, value) do
    if function_call?(zipper) do
      if pipeline?(zipper) do
        zipper
        |> Zipper.down()
        |> case do
          nil ->
            :error

          zipper ->
            {:ok, Zipper.append_child(zipper, value)}
        end
      else
        {:ok, Zipper.append_child(zipper, value)}
      end
    else
      :error
    end
  end

  @doc """
  Checks if the provided function call (in a Zipper) has an argument that equals
  `term` at `index`.
  """
  @spec argument_equals?(Zipper.t(), integer(), any()) :: boolean()
  def argument_equals?(zipper, index, term) do
    if function_call?(zipper) do
      Igniter.Code.Function.argument_matches_predicate?(
        zipper,
        index,
        &Igniter.Code.Common.nodes_equal?(&1, term)
      )
    else
      false
    end
  end

  @doc "Returns true if the argument at the given index matches the provided predicate"
  @spec argument_matches_predicate?(Zipper.t(), non_neg_integer(), (Zipper.t() -> boolean)) ::
          boolean()
  def argument_matches_predicate?(zipper, index, func) do
    if function_call?(zipper) do
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
          |> Zipper.right()
          |> argument_matches_predicate?(index - 1, func)
        end
      else
        case Zipper.node(zipper) do
          {{:., _, [_mod, name]}, _, args} when is_atom(name) and is_list(args) ->
            zipper
            |> Zipper.down()
            |> Common.nth_right(index + 1)
            |> case do
              :error ->
                false

              {:ok, zipper} ->
                zipper
                |> Common.maybe_move_to_single_child_block()
                |> func.()
            end

          _ ->
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
                    |> Common.maybe_move_to_single_child_block()
                    |> func.()
                end
            end
        end
      end
    else
      false
    end
  end

  defp pipeline?(zipper) do
    case zipper.node do
      {:|>, _, _} -> true
      _ -> false
    end
  end
end
