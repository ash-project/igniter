defmodule Igniter.Code.Common do
  @moduledoc """
  General purpose utilities for working with `Sourceror.Zipper`.
  """
  alias Sourceror.Zipper

  @doc """
  Moves to the next node that matches the predicate.
  """
  @spec move_to(Zipper.t(), (Zipper.t() -> boolean())) :: {:ok, Zipper.t()} | :error
  def move_to(zipper, pred) do
    if pred.(zipper) do
      {:ok, zipper}
    else
      case Zipper.next(zipper) do
        nil ->
          :error

        next ->
          move_to(next, pred)
      end
    end
  end

  @doc """
  Returns a list of `zippers` to each `node` that satisfies the `predicate` function, or
  an empty list if none are found.

  The optional second parameters specifies the `direction`, defaults to
  `:next`.
  """
  @spec find_all(Zipper.t(), predicate :: (Zipper.t() -> boolean())) :: [Zipper.t()]
  def find_all(%Zipper{} = zipper, predicate) when is_function(predicate, 1) do
    do_find_all(zipper, predicate, [])
  end

  defp do_find_all(nil, _predicate, buffer), do: Enum.reverse(buffer)

  defp do_find_all(%Zipper{} = zipper, predicate, buffer) do
    if predicate.(zipper) do
      zipper |> Zipper.next() |> do_find_all(predicate, [zipper | buffer])
    else
      zipper |> Zipper.next() |> do_find_all(predicate, buffer)
    end
  end

  @doc """
  Moves to the next node that matches the predicate, going upwards.
  """
  @spec move_upwards(Zipper.t(), (Zipper.t() -> boolean())) :: {:ok, Zipper.t()} | :error
  def move_upwards(zipper, pred) do
    if pred.(zipper) do
      {:ok, zipper}
    else
      case Zipper.up(zipper) do
        nil ->
          :error

        next ->
          move_upwards(next, pred)
      end
    end
  end

  @doc """
  Moves to the last node before the node that matches the predicate, going upwards.
  """
  @spec move_upwards_until(Zipper.t(), (Zipper.t() -> boolean())) :: {:ok, Zipper.t()} | :error
  def move_upwards_until(zipper, pred) do
    if pred.(zipper) do
      {:ok, Zipper.down(zipper) || zipper}
    else
      case Zipper.up(zipper) do
        nil ->
          {:ok, zipper}

        next ->
          move_upwards(next, pred)
      end
    end
  end

  @doc """
  Removes any nodes matching the provided pattern, until there are no matches left.
  """
  @spec remove(Zipper.t(), (Zipper.t() -> boolean)) :: Zipper.t()
  def remove(zipper, pred) do
    case move_to(zipper, pred) do
      {:ok, zipper} ->
        zipper
        |> Zipper.remove()
        |> remove(pred)

      :error ->
        zipper
    end
  end

  @doc """
  Moves to the next zipper that matches the predicate.
  """
  @spec move_to(Zipper.t(), (Zipper.t() -> boolean())) :: {:ok, Zipper.t()} | :error
  def move_to_zipper(zipper, pred) do
    if pred.(zipper) do
      {:ok, zipper}
    else
      if next = Zipper.next(zipper) do
        move_to_zipper(next, pred)
      else
        :error
      end
    end
  end

  @doc """
  Returns `true` if the current node matches the given pattern.

  ## Examples:

  ```elixir
  list_zipper =
    "[1, 2, 3]"
    |> Sourceror.parse_string!()
    |> Sourceror.Zipper.zip()

  Common.node_matches_pattern?(list_zipper, value when is_list(value)) # true
  ```
  """
  defmacro node_matches_pattern?(zipper, pattern) do
    quote do
      ast =
        unquote(zipper)
        |> Igniter.Code.Common.maybe_move_to_single_child_block()
        |> Zipper.node()

      match?(unquote(pattern), ast)
    end
  end

  @doc """
  Moves to the next node that matches the given pattern.
  """
  defmacro move_to_pattern(zipper, pattern) do
    quote do
      case Sourceror.Zipper.find(unquote(zipper), fn
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

  @doc """
  Expands a literal value using the env at the cursor, if possible
  """
  @spec expand_literal(Zipper.t()) :: {:ok, any()} | :error
  def expand_literal(zipper) do
    quoted_literal? =
      case zipper.node do
        {:__block__, _, _} = value ->
          !extendable_block?(value)

        node ->
          Macro.quoted_literal?(node)
      end

    if quoted_literal? do
      {v, _} = Code.eval_quoted(zipper.node)
      {:ok, v}
    else
      case current_env(zipper) do
        {:ok, env} ->
          {:ok, Macro.expand_literals(zipper.node, env)}

        _ ->
          :error
      end
    end
  end

  @doc """
  Adds the provided code to the zipper.

  Use `placement` to determine if the code goes `:after` or `:before` the current node.

  ## Example:

  ```elixir
  existing_zipper = \"\"\"
  IO.inspect("Hello, world!")
  \"\"\"
  |> Sourceror.parse_string!()
  |> Sourceror.Zipper.zip()

  new_code = \"\"\"
  IO.inspect("Goodbye, world!")
  \"\"\"

  existing_zipper
  |> Igniter.Common.add_code(new_code)
  |> Sourceror.Zipper.root()
  |> Sourceror.to_string()
  ```

  Which will produce

  ```elixir
  \"\"\"
  IO.inspect("Hello, world!")
  IO.inspect("Goodbye, world!")
  \"\"\"
  ```
  """
  @spec add_code(Zipper.t(), String.t() | Macro.t(), :after | :before) :: Zipper.t()
  def add_code(zipper, new_code, placement \\ :after)

  def add_code(zipper, new_code, placement) when is_binary(new_code) do
    code = Sourceror.parse_string!(new_code)

    add_code(zipper, code, placement)
  end

  def add_code(zipper, new_code, placement) do
    do_add_code(zipper, new_code, placement)
  end

  defp do_add_code(zipper, new_code, placement, expand_env? \\ true) do
    new_code =
      if expand_env? do
        use_aliases(new_code, zipper)
      else
        new_code
      end

    upwards = Zipper.up(zipper)

    super_upwards =
      if !upwards && zipper.supertree do
        Zipper.up(zipper.supertree)
      end

    cond do
      upwards && extendable_block?(upwards.node) ->
        {:__block__, _, upwards_code} = upwards.node
        index = Enum.count(zipper.path.left || [])

        to_insert =
          if extendable_block?(new_code) do
            {:__block__, _, new_code} = new_code
            new_code
          else
            [new_code]
          end

        {head, tail} =
          if placement == :after do
            Enum.split(upwards_code, index + 1)
          else
            Enum.split(upwards_code, index)
          end

        Zipper.replace(upwards, {:__block__, [], head ++ to_insert ++ tail})

      super_upwards && extendable_block?(super_upwards.node) ->
        {:__block__, _, upwards_code} = super_upwards.node
        index = Enum.count(zipper.supertree.path.left || [])

        to_insert =
          if extendable_block?(new_code) do
            {:__block__, _, new_code} = new_code
            new_code
          else
            [new_code]
          end

        {head, tail} =
          if placement == :after do
            Enum.split(upwards_code, index + 1)
          else
            Enum.split(upwards_code, index)
          end

        new_super_upwards =
          Zipper.replace(super_upwards, {:__block__, [], head ++ to_insert ++ tail})

        if placement == :after do
          %{
            zipper
            | supertree: %{
                zipper.supertree
                | path: %{
                    zipper.supertree.path
                    | parent: new_super_upwards,
                      right: to_insert ++ zipper.supertree.path.right
                  }
              }
          }
        else
          %{
            zipper
            | supertree: %{
                zipper.supertree
                | path: %{
                    zipper.supertree.path
                    | parent: new_super_upwards,
                      left: zipper.supertree.path.right ++ to_insert
                  }
              }
          }
        end

      true ->
        if extendable_block?(zipper.node) && extendable_block?(new_code) do
          {:__block__, _, stuff} = zipper.node

          {:__block__, _, new_stuff} = new_code

          new_stuff =
            if placement == :after do
              stuff ++ new_stuff
            else
              new_stuff ++ stuff
            end

          Zipper.replace(zipper, {:__block__, [], new_stuff})
        else
          if extendable_block?(zipper.node) do
            {:__block__, _, stuff} = zipper.node

            new_stuff =
              if placement == :after do
                stuff ++ [new_code]
              else
                [new_code] ++ stuff
              end

            Zipper.replace(zipper, {:__block__, [], new_stuff})
          else
            code =
              if extendable_block?(new_code) do
                {:__block__, _, new_stuff} = new_code

                if placement == :after do
                  [zipper.node] ++ new_stuff
                else
                  new_stuff ++ [zipper.node]
                end
              else
                if placement == :after do
                  [zipper.node, new_code]
                else
                  [new_code, zipper.node]
                end
              end

            Zipper.replace(zipper, {:__block__, [], code})
          end
        end
    end
  end

  @doc """
  Updates all nodes matching the given predicate with the given function.

  Recurses until the predicate no longer returns false
  """
  @spec update_all_matches(
          Zipper.t(),
          (Zipper.t() -> boolean()),
          (Zipper.t() ->
             {:ok, Zipper.t() | {:code, term()}}
             | {:warning | :error, term()})
        ) ::
          {:ok, Zipper.t()} | {:warning | :error, term()}
  def update_all_matches(zipper, pred, fun) do
    # we check for a single match before traversing as an optimization
    case move_to(zipper, pred) do
      :error ->
        {:ok, zipper}

      {:ok, _} ->
        Zipper.traverse(zipper, false, fn zipper, acc ->
          if pred.(zipper) do
            case fun.(zipper) do
              {:code, new_code} ->
                {replace_code(zipper, new_code), true}

              {:ok, ^zipper} ->
                {zipper, acc}

              {:ok, zipper} ->
                {zipper, true}

              {:halt_depth, zipper} ->
                {zipper, acc}

              other ->
                throw({:other_res, other})
            end
          else
            {zipper, acc}
          end
        end)
        |> case do
          {zipper, false} ->
            {:ok, zipper}

          {zipper, true} ->
            update_all_matches(zipper, pred, fun)
        end
    end
  catch
    {:other_res, v} ->
      v
  end

  def replace_code(zipper, code) when is_binary(code) do
    replace_code(zipper, Sourceror.parse_string!(code))
  end

  def replace_code(zipper, code) do
    code = use_aliases(code, zipper)
    Zipper.replace(zipper, code)
  end

  def extendable_block?(%Zipper{node: node}), do: extendable_block?(node)

  def extendable_block?({:__block__, meta, contents}) when is_list(contents) do
    !meta[:token] && !meta[:format] && !meta[:delimiter]
  end

  def extendable_block?(_), do: false

  @doc """
  Replaces full module names in `new_code` with any aliases for that
  module found in the `current_code` environment.
  """
  def use_aliases(new_code, current_code) do
    case current_env(current_code) do
      {:ok, env} ->
        Macro.prewalk(new_code, fn
          {:__aliases__, _, parts} = node ->
            case use_alias(env, parts) do
              {:alias, new_parts} ->
                {:__aliases__, [], new_parts}

              _ ->
                node
            end

          {{:., _, [{:__aliases__, _, split}, name]}, _, args} = node ->
            if imported?(env, split, name, Enum.count(args)) do
              {name, [], args}
            else
              node
            end

          {{:., _, [{:__aliases__, _, split}, {name, _, context}]}, _, args} = node
          when is_atom(context) ->
            if imported?(env, split, name, Enum.count(args)) do
              {name, [], args}
            else
              node
            end

          {:|>, _,
           [
             arg,
             {{:., _, [{:__aliases__, _, split}, name]}, _, args}
           ]} = node ->
            if imported?(env, split, name, Enum.count(args) + 1) do
              {:|>, [], [arg, {name, [], args}]}
            else
              node
            end

          {:|>, _,
           [
             arg,
             {{:., _, [{:__aliases__, _, split}, {name, _, context}]}, _, args}
           ]} = node
          when is_atom(context) ->
            if imported?(env, split, name, Enum.count(args) + 1) do
              {:|>, [], [arg, {name, [], args}]}
            else
              node
            end

          node ->
            node
        end)

      _ ->
        new_code
    end
  end

  defp imported?(env, split, name, arity) do
    mod = Module.concat(split)

    Enum.any?(env.functions, fn {imported_mod, funs} ->
      mod == imported_mod &&
        Enum.any?(funs, fn {fun_name, fun_arity} ->
          fun_name == name and fun_arity == arity
        end)
    end)
  end

  defp use_alias(env, parts) do
    env.aliases
    |> Enum.filter(fn {_as, fqn} ->
      fqn_split = Enum.map(Module.split(fqn), &String.to_atom/1)
      List.starts_with?(parts, fqn_split)
    end)
    |> Enum.sort_by(fn {_as, fqn} ->
      fqn
      |> Module.split()
      |> Enum.count()
    end)
    |> Enum.reverse()
    |> Enum.at(0)
    |> case do
      nil ->
        :error

      {as, fqn} ->
        to_drop =
          fqn
          |> Module.split()
          |> Enum.count()

        after_as =
          Enum.drop(parts, to_drop)

        as
        |> Module.split()
        |> Enum.map(&String.to_atom/1)
        |> Enum.concat(after_as)
        |> then(&{:alias, &1})
    end
  end

  @doc """
  Moves to a do block for the current call.

  For example, at a node like:

  ```elixir
  foo do
    10
  end
  ```

  You would get a zipper back at `10`.
  """
  @spec move_to_do_block(Zipper.t()) :: {:ok, Zipper.t()} | :error
  def move_to_do_block(zipper) do
    case move_to_pattern(zipper, {{:__block__, _, [:do]}, _}) do
      :error ->
        :error

      {:ok, zipper} ->
        zipper
        |> Zipper.down()
        |> case do
          nil ->
            :error

          zipper ->
            {:ok,
             zipper
             |> Zipper.rightmost()}
        end
    end
  end

  @doc """
  Enters a block with a single child, and moves to that child,
  or returns the zipper unmodified
  """
  @spec maybe_move_to_single_child_block(Zipper.t()) :: Zipper.t()
  def maybe_move_to_single_child_block(nil), do: nil

  def maybe_move_to_single_child_block(zipper) do
    if single_child_block?(zipper) do
      zipper
      |> Zipper.down()
      |> case do
        nil ->
          zipper

        zipper ->
          maybe_move_to_single_child_block(zipper)
      end
    else
      zipper
    end
  end

  @spec single_child_block?(Zipper.t()) :: boolean()
  def single_child_block?(zipper) do
    case zipper.node do
      {:__block__, _, [_]} = block ->
        extendable_block?(block)

      _ ->
        false
    end
  end

  @doc """
  Enters a block, and moves to the first child, or returns the zipper unmodified.
  """
  @spec maybe_move_to_block(Zipper.t()) :: Zipper.t()
  def maybe_move_to_block(nil), do: nil

  def maybe_move_to_block(zipper) do
    case zipper.node do
      {:__block__, _, _} ->
        zipper
        |> Zipper.down()
        |> case do
          nil ->
            zipper

          zipper ->
            zipper
        end

      _ ->
        zipper
    end
  end

  @doc "Moves the zipper right n times, returning `:error` if it can't move that many times."
  @spec nth_right(Zipper.t(), non_neg_integer()) :: {:ok, Zipper.t()} | :error
  def nth_right(zipper, 0) do
    {:ok, zipper}
  end

  def nth_right(zipper, n) do
    zipper
    |> Zipper.right()
    |> case do
      nil ->
        :error

      zipper ->
        nth_right(zipper, n - 1)
    end
  end

  @doc """
  Moves to the cursor that matches the provided pattern or one of the provided patterns, in the current scope.

  See `move_to_cursor/2` for an example of a pattern
  """
  @spec move_to_cursor_match_in_scope(Zipper.t(), String.t() | [String.t()]) ::
          {:ok, Zipper.t()} | :error
  def move_to_cursor_match_in_scope(zipper, patterns) when is_list(patterns) do
    Enum.find_value(patterns, :error, fn pattern ->
      case move_to_cursor_match_in_scope(zipper, pattern) do
        {:ok, value} -> {:ok, value}
        _ -> nil
      end
    end)
  end

  def move_to_cursor_match_in_scope(zipper, pattern) do
    pattern =
      case pattern do
        pattern when is_binary(pattern) ->
          pattern
          |> Sourceror.parse_string!()
          |> Zipper.zip()

        %Zipper{} = pattern ->
          pattern
      end

    case move_to_cursor(zipper, pattern) do
      :error ->
        move_right(zipper, fn zipper ->
          match?({:ok, _}, move_to_cursor(zipper, pattern))
        end)
        |> case do
          {:ok, zipper} ->
            move_to_cursor(zipper, pattern)

          _ ->
            :error
        end

      {:ok, zipper} ->
        {:ok, zipper}
    end
  end

  @doc """
  Moves the zipper all the way to the right, potentially entering a single value block.
  """
  @spec rightmost(Zipper.t()) :: Zipper.t()
  def rightmost(%Zipper{} = zipper) do
    zipper
    |> Zipper.rightmost()
    |> maybe_move_to_single_child_block()
  end

  @doc """
  Moves rightwards, entering blocks (and exiting them if no match is found), until the provided predicate returns `true`.

  Returns `:error` if the end is reached without finding a match.
  """
  @spec move_right(Zipper.t(), (Zipper.t() -> boolean)) :: {:ok, Zipper.t()} | :error
  def move_right(%Zipper{} = zipper, pred) do
    zipper_in_single_child_block = maybe_move_to_single_child_block(zipper)

    cond do
      pred.(zipper) ->
        {:ok, zipper}

      pred.(zipper_in_single_child_block) ->
        {:ok, zipper_in_single_child_block}

      extendable_block?(zipper) && length(elem(zipper.node, 2)) > 1 ->
        zipper
        |> Zipper.down()
        |> case do
          nil ->
            case Zipper.right(zipper) do
              nil ->
                :error

              zipper ->
                move_right(zipper, pred)
            end

          zipper ->
            case move_right(zipper, pred) do
              {:ok, zipper} ->
                {:ok, zipper}

              :error ->
                case Zipper.right(zipper) do
                  nil ->
                    :error

                  zipper ->
                    move_right(zipper, pred)
                end
            end
        end

      true ->
        case Zipper.right(zipper) do
          nil ->
            :error

          zipper ->
            move_right(zipper, pred)
        end
    end
  end

  @doc """
  Moves nextwards (depth-first), until the provided predicate returns `true`.

  Returns `:error` if the end is reached without finding a match.
  """
  @spec move_next(Zipper.t(), (Zipper.t() -> boolean)) :: {:ok, Zipper.t()} | :error
  def move_next(%Zipper{} = zipper, pred) do
    if pred.(zipper) do
      {:ok, zipper}
    else
      case Zipper.next(zipper) do
        nil ->
          :error

        zipper ->
          move_next(zipper, pred)
      end
    end
  end

  @doc """
  Matches and moves to the location of a `__cursor__` in provided source code.

  Use `__cursor__()` to match a cursor in the provided source code. Use `__` to skip any code at a point.

  For example:

  ```elixir
  zipper =
    \"\"\"
    if true do
      10
    end
    \"\"\"
    |> Sourceror.Zipper.zip()

  pattern =
    \"\"\"
    if __ do
      __cursor__()
    end
    \"\"\"

  zipper
  |> Igniter.Code.Common.move_to_cursor(pattern)
  |> Zipper.node()
  # => 10
  ```
  """
  @spec move_to_cursor(Zipper.t(), Zipper.t() | String.t()) :: {:ok, Zipper.t()} | :error
  def move_to_cursor(zipper, pattern) do
    case Zipper.move_to_cursor(zipper, pattern) do
      nil -> :error
      zipper -> {:ok, zipper}
    end
  end

  @doc """
  Expands the environment at the current zipper position and returns the
  expanded environment. Currently used for properly working with aliases.
  """
  def current_env(zipper) do
    Process.put(:elixir_code_diagnostics, {[], false})

    zipper
    |> do_add_code({:__cursor__, [], []}, :after, false)
    |> Zipper.topmost_root()
    |> Sourceror.to_string()
    |> String.split("__cursor__()", parts: 2)
    |> List.first()
    |> Spitfire.container_cursor_to_quoted()
    |> then(fn {:ok, ast} ->
      ast
    end)
    |> Spitfire.Env.expand("file.ex")
    |> then(fn {_ast, _final_state, _final_env, cursor_env} ->
      {:ok, struct(Macro.Env, cursor_env)}
    end)
  rescue
    e ->
      {:error, e}
  after
    Process.delete(:elixir_code_diagnostics)
  end

  @doc """
  Runs the function `fun` on the subtree of the currently focused `node` and
  returns the updated `zipper`.

  `fun` must return {:ok, zipper} or `:error`, which may be positioned at the top of the subtree.
  """
  def within(%Zipper{} = top_zipper, fun) when is_function(fun, 1) do
    top_zipper
    |> Zipper.subtree()
    |> fun.()
    |> case do
      :error ->
        :error

      {:ok, zipper} ->
        {:ok,
         zipper
         |> Zipper.top()
         |> into(zipper.supertree || top_zipper)}
    end
  end

  @spec nodes_equal?(Zipper.t() | Macro.t(), Macro.t()) :: boolean
  def nodes_equal?(%Zipper{} = left, right) do
    with zipper when not is_nil(zipper) <- Zipper.up(left),
         {:defmodule, _, [{:__aliases__, _, parts}, _]} <- Zipper.node(zipper),
         {:ok, env} <- current_env(zipper),
         true <- nodes_equal?({:__aliases__, [], [Module.concat([env.module | parts])]}, right) do
      true
    else
      _ ->
        left
        |> expand_aliases()
        |> Zipper.node()
        |> nodes_equal?(right)
    end
  end

  def nodes_equal?(_left, %Zipper{}) do
    raise ArgumentError, "right side of `nodes_equal?` must not be a zipper"
  end

  def nodes_equal?(v, v), do: true

  def nodes_equal?(l, r) do
    equal_vals?(l, r)
  end

  defp equal_vals?(same, same), do: true

  defp equal_vals?({:__block__, _, [value]}, value) do
    true
  end

  defp equal_vals?(value, {:__block__, _, [value]}) do
    true
  end

  defp equal_vals?(
         {:sigil_r, _, [{:<<>>, _, [left_contents]}, left_flags]},
         {:sigil_r, _, [{:<<>>, _, [right_contents]}, right_flags]}
       ) do
    equal_vals?(left_contents, right_contents) and equal_vals?(left_flags, right_flags)
  end

  defp equal_vals?(left, right) do
    cond do
      extendable_block?(left) ->
        case left do
          {:__block__, _, [left]} ->
            nodes_equal?(left, right)

          _ ->
            equal_modules?(left, right)
        end

      extendable_block?(right) ->
        case right do
          {:__block__, _, [right]} ->
            nodes_equal?(left, right)

          _ ->
            equal_modules?(left, right)
        end

      is_list(left) and is_list(right) ->
        length(left) == length(right) and
          Enum.all?(Enum.zip(left, right), fn {l, r} -> nodes_equal?(l, r) end)

      true ->
        equal_modules?(left, right)
    end
  end

  @spec expand_alias(Zipper.t()) :: Zipper.t()
  def expand_alias(zipper) do
    case zipper.node do
      {:__aliases__, _, parts} ->
        case current_env(zipper) do
          {:ok, env} ->
            case do_expand_alias(env, [], parts) do
              {:alias, value} ->
                Zipper.replace(
                  zipper,
                  {:__aliases__, [], Enum.map(Module.split(value), &String.to_atom/1)}
                )

              _ ->
                zipper
            end

          _ ->
            zipper
        end

      _ ->
        zipper
    end
  rescue
    _ ->
      zipper
  end

  if Code.ensure_loaded?(Macro.Env) && function_exported?(Macro.Env, :expand_alias, 3) do
    defp do_expand_alias(env, meta, parts) do
      Macro.Env.expand_alias(env, meta, parts)
    end
  else
    defp do_expand_alias(_env, _meta, _parts) do
      :error
    end
  end

  @spec expand_aliases(Zipper.t()) :: Zipper.t()
  def expand_aliases(zipper) do
    Zipper.traverse(zipper, &expand_alias/1)
  end

  # aliases will confuse this, but that is a later problem :)
  # probably the best thing we can do here is a pre-processing alias replacement pass?
  # or I guess we'll have to pass the igniter in which tracks alias sources? Hard to say.
  defp equal_modules?({:__aliases__, _, mod}, {:__aliases__, _, mod}), do: true

  defp equal_modules?({:__aliases__, _, mod}, right) when is_atom(right) do
    Module.concat(mod) == right
  end

  defp equal_modules?(left, {:__aliases__, _, mod}) when is_atom(left) do
    Module.concat(mod) == left
  end

  defp equal_modules?(_left, _right) do
    false
  end

  @compile {:inline, into: 2}

  defp into(%Zipper{path: nil} = zipper, %Zipper{path: path, supertree: supertree}),
    do: %{zipper | path: path, supertree: supertree}
end
