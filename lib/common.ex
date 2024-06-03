defmodule Igniter.Common do
  @moduledoc """
  Common utilities for working with igniter, primarily with `Sourceror.Zipper`.
  """
  alias Sourceror.Zipper

  def find(zipper, direction \\ :next, pred) do
    Zipper.find(zipper, direction, fn thing ->
      try do
        pred.(thing)
      rescue
        FunctionClauseError ->
          false
      end
    end)
  end

  defmacro node_matches_pattern?(zipper, pattern) do
    quote do
      ast =
        unquote(zipper)
        |> Igniter.Common.maybe_move_to_block()
        |> Zipper.subtree()
        |> Zipper.root()

      match?(unquote(pattern), ast)
    end
  end

  defmacro move_to_pattern(zipper, direction \\ :next, pattern) do
    quote do
      case Sourceror.Zipper.find(unquote(zipper), unquote(direction), fn
             unquote(pattern) ->
               true

             _ ->
               false
           end) do
        nil -> :error
        value -> {:ok, value}
      end
    end
  end

  defmacro argument_matches_pattern?(zipper, index, pattern) do
    quote do
      Igniter.Common.argument_matches_predicate?(
        unquote(zipper),
        unquote(index),
        &match?(unquote(pattern), &1)
      )
    end
  end

  def puts_code_at_node(zipper) do
    zipper
    |> Zipper.subtree()
    |> Zipper.root()
    |> Sourceror.to_string()
    |> then(&"==code==\n#{&1}\n==code==\n")
    |> IO.puts()

    zipper
  end

  def puts_ast_at_node(zipper) do
    zipper
    |> Zipper.subtree()
    |> Zipper.root()
    |> then(&"==ast==\n#{inspect(&1)}\n==ast==\n")
    |> IO.puts()

    zipper
  end

  def add_code(zipper, new_code) when is_binary(new_code) do
    code = Sourceror.parse_string!(new_code)

    add_code(zipper, code)
  end

  def add_code(zipper, new_code) do
    current_code =
      zipper
      |> Zipper.subtree()
      |> Zipper.root()

    case current_code do
      {:__block__, meta, stuff} ->
        Zipper.replace(zipper, {:__block__, meta, stuff ++ [new_code]})

      code ->
        zipper
        |> Zipper.up()
        |> case do
          nil ->
            Zipper.replace(zipper, {:__block__, [], [code, new_code]})

          upwards ->
            upwards
            |> Zipper.subtree()
            |> Zipper.root()
            |> case do
              {:__block__, meta, stuff} ->
                Zipper.replace(upwards, {:__block__, meta, stuff ++ [new_code]})

              _ ->
                Zipper.replace(zipper, {:__block__, [], [code, new_code]})
            end
        end
    end
  end

  def put_in_keyword(zipper, path, value, updater \\ nil) do
    updater = updater || fn _ -> value end

    do_put_in_keyword(zipper, path, value, updater)
  end

  defp do_put_in_keyword(zipper, [key], value, updater) do
    set_keyword_key(zipper, key, value, updater)
  end

  defp do_put_in_keyword(zipper, [key | rest], value, updater) do
    if node_matches_pattern?(zipper, value when is_list(value)) do
      case move_to_list_item(zipper, fn item ->
             if tuple?(item) do
               first_elem = tuple_elem(item, 0)
               first_elem && node_matches_pattern?(first_elem, ^key)
             end
           end) do
        :error ->
          value =
            keywordify(rest, value)

          {:ok,
           prepend_to_list(
             zipper,
             [{key, value}]
           )}

        {:ok, zipper} ->
          zipper
          |> tuple_elem(1)
          |> case do
            nil ->
              :error

            zipper ->
              do_put_in_keyword(zipper, rest, value, updater)
          end
      end
    end
  end

  def set_keyword_key(zipper, key, value, updater) do
    if node_matches_pattern?(zipper, value when is_list(value)) do
      case move_to_list_item(zipper, fn item ->
             if tuple?(item) do
               first_elem = tuple_elem(item, 0)
               first_elem && node_matches_pattern?(first_elem, ^key)
             end
           end) do
        :error ->
          {:ok,
           prepend_to_list(
             zipper,
             {{:__block__, [format: :keyword], [key]}, {:__block__, [], [value]}}
           )}

        {:ok, zipper} ->
          zipper
          |> tuple_elem(1)
          |> case do
            nil ->
              :error

            zipper ->
              {:ok, updater.(zipper)}
          end
      end
    end
  end

  def put_in_map(zipper, path, value, updater \\ nil) do
    updater = updater || fn _ -> value end

    do_put_in_map(zipper, path, value, updater)
  end

  defp do_put_in_map(zipper, [key], value, updater) do
    set_map_key(zipper, key, value, updater)
  end

  defp do_put_in_map(zipper, [key | rest], value, updater) do
    cond do
      node_matches_pattern?(zipper, {:%{}, _, []}) ->
        {:ok,
         Zipper.append_child(
           zipper,
           mappify([key | rest], value)
         )}

      node_matches_pattern?(zipper, {:%{}, _, _}) ->
        zipper
        |> Zipper.down()
        |> move_to_list_item(fn item ->
          if tuple?(item) do
            first_elem = tuple_elem(item, 0)
            first_elem && node_matches_pattern?(first_elem, ^key)
          end
        end)
        |> case do
          :error ->
            format = map_keys_format(zipper)
            value = mappify(rest, value)

            {:ok,
             prepend_to_list(
               zipper,
               {{:__block__, [format: format], [key]}, {:__block__, [], [value]}}
             )}

          {:ok, zipper} ->
            zipper
            |> tuple_elem(1)
            |> case do
              nil ->
                :error

              zipper ->
                do_put_in_map(zipper, rest, value, updater)
            end
        end

      true ->
        :error
    end
  end

  def set_map_key(zipper, key, value, updater) do
    cond do
      node_matches_pattern?(zipper, {:%{}, _, []}) ->
        {:ok,
         Zipper.append_child(
           zipper,
           mappify([key], value)
         )}

      node_matches_pattern?(zipper, {:%{}, _, _}) ->
        zipper
        |> Zipper.down()
        |> move_to_list_item(fn item ->
          if tuple?(item) do
            first_elem = tuple_elem(item, 0)
            first_elem && node_matches_pattern?(first_elem, ^key)
          end
        end)
        |> case do
          :error ->
            format = map_keys_format(zipper)

            {:ok,
             prepend_to_list(
               zipper,
               {{:__block__, [format: format], [key]}, {:__block__, [], [value]}}
             )}

          {:ok, zipper} ->
            zipper
            |> tuple_elem(1)
            |> case do
              nil ->
                :error

              zipper ->
                {:ok, updater.(zipper)}
            end
        end

      true ->
        :error
    end
  end

  defp map_keys_format(zipper) do
    zipper
    |> Zipper.subtree()
    |> Zipper.node()
    |> case do
      value when is_list(value) ->
        Enum.all?(value, fn
          {:__block__, meta, _} ->
            meta[:format] == :keyword

          _ ->
            false
        end)
        |> case do
          true ->
            :keyword

          false ->
            :map
        end

      _ ->
        :map
    end
  end

  def move_to_function_call_in_current_scope(zipper, name, arity, predicate \\ fn _ -> true end) do
    zipper
    |> maybe_move_to_block()
    |> move_right(fn zipper ->
      function_call?(zipper, name, arity) && predicate.(zipper)
    end)
  end

  def function_call?(zipper, name, arity) do
    zipper
    |> maybe_move_to_block()
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
                |> nth_right(index)
                |> case do
                  :error ->
                    nil

                  {:ok, nth} ->
                    {:ok, func.(nth)}
                end
            end
        end
      end
    else
      zipper
      |> Zipper.down()
      |> case do
        nil ->
          nil

        zipper ->
          zipper
          |> nth_right(index)
          |> case do
            :error ->
              :error

            {:ok, nth} ->
              {:ok, func.(nth)}
          end
      end
    end
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
                |> nth_right(index - 1)
                |> case do
                  :error ->
                    false

                  {:ok, zipper} ->
                    zipper
                    |> maybe_move_to_block()
                    |> Zipper.subtree()
                    |> Zipper.root()
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
          |> nth_right(index)
          |> case do
            :error ->
              false

            {:ok, zipper} ->
              zipper
              |> maybe_move_to_block()
              |> Zipper.subtree()
              |> Zipper.root()
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

  # sobelow_skip ["DOS.StringToAtom"]
  def move_to_module_using(zipper, module) do
    split_module =
      module
      |> Module.split()
      |> Enum.map(&String.to_atom/1)

    with {:ok, zipper} <- move_to_pattern(zipper, {:defmodule, _, [_, _]}),
         subtree <- Zipper.subtree(zipper),
         subtree <- subtree |> Zipper.down() |> Zipper.rightmost(),
         subtree <- remove_module_definitions(subtree),
         found when not is_nil(found) <-
           find(subtree, fn
             {:use, _, [^module | _]} ->
               true

             {:use, _, [{:__aliases__, _, ^split_module} | _]} ->
               true
           end),
         {:ok, zipper} <- move_to_do_block(zipper) do
      {:ok, zipper}
    else
      _ ->
        :error
    end
  end

  # aliases will confuse this, but that is a later problem :)
  def equal_modules?(zipper, module) do
    root =
      zipper
      |> Zipper.subtree()
      |> Zipper.root()

    do_equal_modules?(root, module)
  end

  defp do_equal_modules?(left, left), do: true
  defp do_equal_modules?({:__aliases__, _, mod}, {:__aliases__, _, mod}), do: true

  defp do_equal_modules?({:__aliases__, _, mod}, right) when is_atom(right) do
    Module.concat(mod) == right
  end

  defp do_equal_modules?(left, {:__aliases__, _, mod}) when is_atom(left) do
    Module.concat(mod) == left
  end

  defp do_equal_modules?(_, _), do: false

  def move_to_defp(zipper, fun, arity) do
    case move_to_pattern(zipper, {:defp, _, [{^fun, _, args}, _]} when length(args) == arity) do
      :error ->
        if arity == 0 do
          case move_to_pattern(zipper, {:defp, _, [{^fun, _, context}, _]} when is_atom(context)) do
            :error ->
              :error

            {:ok, zipper} ->
              move_to_do_block(zipper)
          end
        else
          :error
        end

      {:ok, zipper} ->
        move_to_do_block(zipper)
    end
  end

  def move_to_do_block(zipper) do
    case move_to_pattern(zipper, {{:__block__, _, [:do]}, _}) do
      :error ->
        :error

      {:ok, zipper} ->
        {:ok,
         zipper
         |> Zipper.down()
         |> Zipper.rightmost()
         |> maybe_move_to_block()}
    end
  end

  def maybe_move_to_block(nil), do: nil

  def maybe_move_to_block(zipper) do
    zipper
    |> Zipper.subtree()
    |> Zipper.root()
    |> case do
      {:__block__, _, _} ->
        zipper
        |> Zipper.down()
        |> maybe_move_to_block()

      _ ->
        zipper
    end
  end

  def remove_module_definitions(zipper) do
    Zipper.traverse(zipper, fn
      {:defmodule, _, _} ->
        nil

      other ->
        other
    end)
  end

  def prepend_new_to_list(zipper, quoted, equality_pred \\ &default_equality_pred/2) do
    zipper
    |> find_list_item_index(fn value ->
      equality_pred.(value, quoted)
    end)
    |> case do
      :error ->
        zipper
        |> maybe_move_to_block()
        |> Zipper.insert_child(quoted)

      _ ->
        zipper
    end
  end

  defp default_equality_pred(zipper, quoted) do
    zipper
    |> Zipper.subtree()
    |> Zipper.root()
    |> Kernel.==(quoted)
  end

  def prepend_to_list(zipper, quoted) do
    zipper
    |> maybe_move_to_block()
    |> Zipper.insert_child(quoted)
  end

  def remove_index(zipper, index) do
    zipper
    |> maybe_move_to_block()
    |> Zipper.down()
    |> case do
      nil ->
        zipper

      zipper ->
        zipper
        |> do_remove_index(index)
    end
  end

  defp do_remove_index(zipper, 0) do
    Zipper.remove(zipper)
  end

  defp do_remove_index(zipper, i) do
    zipper
    |> Zipper.right()
    |> case do
      nil ->
        zipper

      zipper ->
        zipper
        |> do_remove_index(i - 1)
    end
  end

  defp nth_right(zipper, 0) do
    {:ok, zipper}
  end

  defp nth_right(zipper, n) do
    zipper
    |> Zipper.right()
    |> case do
      nil ->
        :error

      zipper ->
        nth_right(zipper, n - 1)
    end
  end

  def find_list_item_index(zipper, pred) do
    # go into first list item
    zipper
    |> maybe_move_to_block()
    |> Zipper.down()
    |> case do
      nil ->
        :error

      zipper ->
        find_index_right(zipper, pred, 0)
    end
  end

  def move_to_list_item(zipper, pred) do
    # go into first list item
    zipper
    |> maybe_move_to_block()
    |> Zipper.down()
    |> case do
      nil ->
        :error

      zipper ->
        move_right(zipper, pred)
    end
  end

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

  def tuple_elem(item, elem) do
    item
    |> maybe_move_to_block()
    |> Zipper.down()
    |> go_right_n_times(elem)
    |> maybe_move_to_block()
  end

  defp go_right_n_times(zipper, 0), do: maybe_move_to_block(zipper)

  defp go_right_n_times(zipper, n) do
    zipper
    |> Zipper.right()
    |> case do
      nil -> nil
      zipper -> go_right_n_times(zipper, n - 1)
    end
  end

  defp find_index_right(zipper, pred, index) do
    if pred.(maybe_move_to_block(zipper)) do
      {:ok, index}
    else
      case Zipper.right(zipper) do
        nil ->
          :error

        zipper ->
          zipper
          |> find_index_right(pred, index + 1)
      end
    end
  end

  defp move_right(zipper, pred) do
    zipper_in_block = maybe_move_to_block(zipper)

    if pred.(zipper_in_block) do
      {:ok, zipper_in_block}
    else
      case Zipper.right(zipper) do
        nil ->
          :error

        zipper ->
          zipper
          |> move_right(pred)
      end
    end
  end

  @doc false
  def keywordify([], value) do
    value
  end

  def keywordify([key | rest], value) do
    [{key, keywordify(rest, value)}]
  end

  @doc false
  def mappify([], value) do
    value
  end

  def mappify([key | rest], value) do
    format =
      if is_atom(key) do
        :keyword
      else
        :map
      end

    {:%{}, [], [{{:__block__, [format: format], [key]}, mappify(rest, value)}]}
  end
end
