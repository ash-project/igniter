defmodule Igniter.Common do
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
        |> Igniter.Common.maybe_enter_block()
        |> Zipper.subtree()
        |> Zipper.root()

      match?(unquote(pattern), ast)
    end
  end

  defmacro find_pattern(zipper, direction \\ :next, pattern) do
    quote do
      Sourceror.Zipper.find(unquote(zipper), unquote(direction), fn
        unquote(pattern) ->
          true

        _ ->
          false
      end)
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
    |> IO.puts()

    zipper
  end

  def add_code(zipper, new_code) do
    current_code =
      zipper
      |> Zipper.subtree()
      |> Zipper.root()
      |> IO.inspect()

    case current_code do
      {:__block__, block_meta, stuff} ->
        Zipper.replace(zipper, {:__block__, block_meta, stuff ++ [new_code]})

      code ->
        Zipper.replace(zipper, {:__block__, [], [code, new_code]})
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
      case find_list_item(zipper, fn item ->
             if is_tuple?(item) do
               first_elem = tuple_elem(item, 0)
               first_elem && node_matches_pattern?(first_elem, ^key)
             end
           end) do
        nil ->
          value = keywordify(rest, value)

          prepend_to_list(
            zipper,
            {{:__block__, [format: :keyword], [key]}, {:__block__, [], [value]}}
          )

        zipper ->
          zipper
          |> tuple_elem(1)
          |> case do
            nil ->
              nil

            zipper ->
              do_put_in_keyword(zipper, rest, value, updater)
          end
      end
    end
  end

  def set_keyword_key(zipper, key, value, updater) do
    if node_matches_pattern?(zipper, value when is_list(value)) do
      case find_list_item(zipper, fn item ->
             if is_tuple?(item) do
               first_elem = tuple_elem(item, 0)
               first_elem && node_matches_pattern?(first_elem, ^key)
             end
           end) do
        nil ->
          prepend_to_list(
            zipper,
            {{:__block__, [format: :keyword], [key]}, {:__block__, [], [value]}}
          )

        zipper ->
          zipper
          |> tuple_elem(1)
          |> case do
            nil ->
              nil

            zipper ->
              updater.(zipper)
          end
      end
    end
  end

  def find_function_call_in_current_scope(zipper, name, arity, predicate \\ fn _ -> true end) do
    case Zipper.down(zipper) do
      nil ->
        nil

      zipper ->
        find_right(zipper, fn zipper ->
          is_function_call(zipper, name, arity) && predicate.(zipper)
        end)
    end
  end

  def is_function_call(zipper, name, arity) do
    zipper
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
    if is_pipeline?(zipper) do
      if index == 0 do
        zipper
        |> Zipper.down()
        |> case do
          nil ->
            nil

          zipper ->
            func.(zipper)
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
                |> nth_right(index)
                |> case do
                  nil ->
                    nil

                  nth ->
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
          nil

        zipper ->
          zipper
          |> nth_right(index)
          |> case do
            nil ->
              nil

            nth ->
              func.(nth)
          end
      end
    end
  end

  def argument_matches_predicate?(zipper, index, func) do
    if is_pipeline?(zipper) do
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
                |> maybe_enter_block()
                |> Zipper.subtree()
                |> Zipper.root()
                |> func.()
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
          |> maybe_enter_block()
          |> Zipper.subtree()
          |> Zipper.root()
          |> func.()
      end
    end
  end

  def is_pipeline?(zipper) do
    zipper
    |> Zipper.subtree()
    |> Zipper.root()
    |> case do
      {:|>, _, _} -> true
      _ -> false
    end
  end

  def move_to_module_using(zipper, module) do
    split_module =
      module
      |> Module.split()
      |> Enum.map(&String.to_atom/1)

    with zipper when not is_nil(zipper) <- find_pattern(zipper, {:defmodule, _, [_, _]}),
         subtree <- Zipper.subtree(zipper),
         subtree <- subtree |> Zipper.down() |> Zipper.rightmost(),
         subtree <- remove_module_definitions(subtree),
         found when not is_nil(found) <-
           find(subtree, fn
             {:use, _, [^module]} ->
               true

             {:use, _, [{:__aliases__, _, ^split_module}]} ->
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
    case find_pattern(zipper, {:defp, _, [{^fun, _, args}, _]} when length(args) == arity) do
      nil ->
        if arity == 0 do
          case find_pattern(zipper, {:defp, _, [{^fun, _, context}, _]} when is_atom(context)) do
            nil ->
              :error

            zipper ->
              move_to_do_block(zipper)
          end
        else
          :error
        end

      zipper ->
        move_to_do_block(zipper)
    end
  end

  def move_to_do_block(zipper) do
    case find_pattern(zipper, {{:__block__, _, [:do]}, _}) do
      nil ->
        :error

      zipper ->
        {:ok,
         zipper
         |> Zipper.down()
         |> Zipper.rightmost()
         |> maybe_enter_block()}
    end
  end

  def maybe_enter_block(nil), do: nil

  def maybe_enter_block(zipper) do
    zipper
    |> Zipper.subtree()
    |> Zipper.root()
    |> case do
      {:__block__, _, [_]} ->
        Zipper.down(zipper)

      _ ->
        zipper
    end
  end

  def remove_module_definitions(zipper) do
    Sourceror.Zipper.traverse(zipper, fn
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
      nil ->
        zipper
        |> maybe_enter_block()
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
    |> maybe_enter_block()
    |> Zipper.insert_child(quoted)
  end

  def remove_index(zipper, index) do
    zipper
    |> maybe_enter_block()
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
    zipper
  end

  defp nth_right(zipper, n) do
    zipper
    |> Zipper.right()
    |> case do
      nil ->
        nil

      zipper ->
        nth_right(zipper, n - 1)
    end
  end

  def find_list_item_index(zipper, pred) do
    # go into first list item
    zipper
    |> maybe_enter_block()
    |> Zipper.down()
    |> case do
      nil ->
        nil

      zipper ->
        find_index_right(zipper, pred, 0)
    end
  end

  def find_list_item(zipper, pred) do
    # go into first list item
    zipper
    |> maybe_enter_block()
    |> Zipper.down()
    |> case do
      nil ->
        nil

      zipper ->
        find_right(zipper, pred)
    end
  end

  def is_tuple?(item) do
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
    |> maybe_enter_block()
    |> Zipper.down()
    |> go_right_n_times(elem)
    |> maybe_enter_block()
  end

  defp go_right_n_times(zipper, 0), do: maybe_enter_block(zipper)

  defp go_right_n_times(zipper, n) do
    zipper
    |> Zipper.right()
    |> case do
      nil -> nil
      zipper -> go_right_n_times(zipper, n - 1)
    end
  end

  defp find_index_right(zipper, pred, index) do
    if pred.(maybe_enter_block(zipper)) do
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

  defp find_right(zipper, pred) do
    if pred.(maybe_enter_block(zipper)) do
      zipper
    else
      case Zipper.right(zipper) do
        nil ->
          nil

        zipper ->
          zipper
          |> find_right(pred)
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
end
