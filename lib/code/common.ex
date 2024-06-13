defmodule Igniter.Code.Common do
  @moduledoc """
  General purpose utilities for working with `Sourceror.Zipper`.
  """
  alias Sourceror.Zipper

  @doc """
  Moves to the next node that matches the predicate.
  """
  @spec move_to(Zipper.t(), (Zipper.tree() -> Zipper.t())) :: {:ok, Zipper.t()} | :error
  def move_to(zipper, pred) do
    Zipper.find(zipper, fn thing ->
      try do
        pred.(thing)
      rescue
        FunctionClauseError ->
          false
      end
    end)
    |> case do
      nil ->
        :error

      zipper ->
        {:ok, zipper}
    end
  end

  @doc """
  Returns `true` if the current node matches the given pattern.
  """
  defmacro node_matches_pattern?(zipper, pattern) do
    quote do
      ast =
        unquote(zipper)
        |> Igniter.Code.Common.maybe_move_to_block()
        |> Zipper.subtree()
        |> Zipper.root()

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
  Adds the provided code to the zipper.

  Use the `placement` to determine if the code goes `:after` or `:before` the current node.

  ## Example:

  ```elixir
  existing_code = \"\"\"
  IO.inspect("Hello, world!")
  \"\"\"
  |> Sourceror.parse_string!()

  new_code = \"\"\"
  IO.inspect("Goodbye, world!")
  \"\"\"

  existing_code
  |> Sourceror.Zipper.zip()
  |> Igniter.Common.add_code(new_code)
  |> Sourceror.Zipper.root()
  |> Sourceror.to_string()
  ```

  Which will produce

  ```elixir
  \"\"\"
  IO.inspect("Hello, world!")
  |> Sourceror.to_string()
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
    current_code =
      zipper
      |> Zipper.subtree()
      |> Zipper.root()

    case current_code do
      {:__block__, meta, stuff} ->
        new_stuff =
          if placement == :after do
            stuff ++ [new_code]
          else
            [new_code | stuff]
          end

        Zipper.replace(zipper, {:__block__, meta, new_stuff})

      code ->
        zipper
        |> Zipper.up()
        |> case do
          nil ->
            if placement == :after do
              Zipper.replace(zipper, {:__block__, [], [code, new_code]})
            else
              Zipper.replace(zipper, {:__block__, [], [new_code, code]})
            end

          upwards ->
            upwards
            |> Zipper.subtree()
            |> Zipper.root()
            |> case do
              {:__block__, meta, stuff} ->
                new_stuff =
                  if placement == :after do
                    stuff ++ [new_code]
                  else
                    case stuff do
                      [first | rest] ->
                        [first, new_code | rest]

                      _ ->
                        [new_code | stuff]
                    end
                  end

                Zipper.replace(upwards, {:__block__, meta, new_stuff})

              _ ->
                if placement == :after do
                  Zipper.replace(zipper, {:__block__, [], [code, new_code]})
                else
                  Zipper.replace(zipper, {:__block__, [], [new_code, code]})
                end
            end
        end
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
             |> Zipper.rightmost()
             |> maybe_move_to_block()}
        end
    end
  end

  @doc """
  Enters a block with a single child, and moves to that child,
  or returns the zipper unmodified
  """
  @spec maybe_move_to_block(Zipper.t()) :: Zipper.t()
  def maybe_move_to_block(nil), do: nil

  def maybe_move_to_block(zipper) do
    zipper
    |> Zipper.subtree()
    |> Zipper.root()
    |> case do
      {:__block__, _, [_]} ->
        zipper
        |> Zipper.down()
        |> case do
          nil ->
            zipper

          zipper ->
            maybe_move_to_block(zipper)
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

    case move_right(zipper, &move_to_cursor(&1, pattern)) do
      :error ->
        :error

      {:ok, zipper} ->
        move_to_cursor(zipper, pattern)
    end
  end

  @doc """
  Moves right in the zipper, until the provided predicate returns `true`.

  Returns `:error` if the end is reached without finding a match.
  """
  @spec move_right(Zipper.t(), (Zipper.t() -> boolean)) :: {:ok, Zipper.t()} | :error
  def move_right(%Zipper{} = zipper, pred) do
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

  # keeping in mind that version returns `nil` on no match
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
      __cursor__
    end
    \"\"\"

  zipper
  |> Igniter.Code.Common.move_to_cursor(pattern)
  |> Zipper.subtree()
  |> Zipper.node()
  # => 10
  ```
  """
  @spec move_to_cursor(Zipper.t(), Zipper.t() | String.t()) :: {:ok, Zipper.t()} | :error
  def move_to_cursor(%Zipper{} = zipper, pattern) when is_binary(pattern) do
    pattern
    |> Sourceror.parse_string!()
    |> Zipper.zip()
    |> then(&do_move_to_cursor(zipper, &1))
  end

  def move_to_cursor(%Zipper{} = zipper, %Zipper{} = pattern_zipper) do
    do_move_to_cursor(zipper, pattern_zipper)
  end

  defp do_move_to_cursor(%Zipper{} = zipper, %Zipper{} = pattern_zipper) do
    cond do
      cursor?(pattern_zipper |> Zipper.subtree() |> Zipper.node()) ->
        {:ok, zipper}

      match_type = zippers_match(zipper, pattern_zipper) ->
        move =
          case match_type do
            :skip -> &Zipper.skip/1
            :next -> &Zipper.next/1
          end

        with zipper when not is_nil(zipper) <- move.(zipper),
             pattern_zipper when not is_nil(pattern_zipper) <- move.(pattern_zipper) do
          do_move_to_cursor(zipper, pattern_zipper)
        end

      true ->
        :error
    end
  end

  defp cursor?({:__cursor__, _, []}), do: true
  defp cursor?(_other), do: false

  defp zippers_match(zipper, pattern_zipper) do
    zipper_node =
      zipper
      |> Zipper.subtree()
      |> Zipper.node()

    pattern_node =
      pattern_zipper
      |> Zipper.subtree()
      |> Zipper.node()

    case {zipper_node, pattern_node} do
      {_, {:__, _, _}} ->
        :skip

      {{call, _, _}, {call, _, _}} ->
        :next

      {{_, _}, {_, _}} ->
        :next

      {same, same} ->
        :next

      {left, right} when is_list(left) and is_list(right) ->
        :next

      _ ->
        false
    end
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
         |> into(top_zipper)}
    end
  end

  @spec nodes_equal?(Zipper.t() | Macro.t(), Zipper.t() | Macro.t()) :: boolean
  def nodes_equal?(%Zipper{} = left, right) do
    left
    |> Zipper.subtree()
    |> Zipper.node()
    |> nodes_equal?(right)
  end

  def nodes_equal?(left, %Zipper{} = right) do
    right
    |> Zipper.subtree()
    |> Zipper.node()
    |> then(&nodes_equal?(left, &1))
  end

  def nodes_equal?(v, v), do: true

  def nodes_equal?(l, r) do
    equal_modules?(l, r)
  end

  @compile {:inline, into: 2}
  defp into(%Zipper{path: nil} = zipper, %Zipper{path: path}), do: %{zipper | path: path}

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
end
