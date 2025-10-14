# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs.contributors>
#
# SPDX-License-Identifier: MIT

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

  @spec move_to_defp(Zipper.t(), fun :: atom, arity :: integer | list(integer), Keyword.t()) ::
          {:ok, Zipper.t()} | :error
  def move_to_defp(zipper, fun, arity, opts \\ []) do
    opts = Keyword.put(opts, :target, Keyword.get(opts, :target, :inside))

    do_move_to_def(zipper, fun, arity, :defp, opts)
  end

  @spec move_to_def(Zipper.t(), Keyword.t()) :: {:ok, Zipper.t()} | :error
  def move_to_def(zipper, opts \\ []) do
    opts = Keyword.put(opts, :target, Keyword.get(opts, :target, :at))

    case move_to_function_call(zipper, :def, :any) do
      {:ok, zipper} ->
        move_to_target(zipper, Keyword.get(opts, :target, :inside))

      :error ->
        :error
    end
  end

  @doc """
  Moves the zipper to a function definition by the given name and arity. You may
  also pass in a :target option to specify where in the function you want to
  move to. By default it will move to the inside of the function.
  The `:target` option can be one of the following:
  - `:inside` - moves to the inside of the function
  - `:before` - moves to before the function and takes into consideration the
    attributes `@doc`, `@spec`, and `@impl` if they exist
  - `:at` - moves to the function definition itself. Use this if you want to add
    code directly before or directly after the function.

  ## Example - Moves before the function.

  ```elixir
  zipper =
    \"\"\"
    defmodule Test do
      @doc "hello"
      @spec hello() :: :world
      def hello() do
        :world
      end
    end
    \"\"\"
    |> Sourceror.parse_string!()
    |> Zipper.zip()

  {:ok, zipper} = Igniter.Code.Function.move_to_function_and_attrs(zipper, :hello, 0)

  zipper =
    Igniter.Code.Common.add_code(
      zipper,
      \"\"\"
      def world() do
        :hello
      end
      \"\"\",
      placement: :before
    )

  Igniter.Util.Debug.code_at_node(Zipper.topmost(zipper))
  # defmodule Test do
  #   def world() do
  #     :hello
  #   end
  #
  #   @doc "hello"
  #   @spec hello() :: :world
  #   def hello() do
  #     :world
  #   end
  # end
  ```
  """
  @spec move_to_def(Zipper.t(), fun :: atom, arity :: integer | list(integer) | :any, Keyword.t()) ::
          {:ok, Zipper.t()} | :error
  def move_to_def(zipper, fun, arity, opts \\ []) do
    opts = Keyword.put(opts, :target, Keyword.get(opts, :target, :inside))
    do_move_to_def(zipper, fun, arity, :def, opts)
  end

  defp do_move_to_def(zipper, fun, [arity], kind, opts) do
    do_move_to_def(zipper, fun, arity, kind, opts)
  end

  defp do_move_to_def(zipper, fun, [arity | rest], kind, opts) do
    case do_move_to_def(zipper, fun, arity, kind, opts) do
      {:ok, zipper} -> {:ok, zipper}
      :error -> do_move_to_def(zipper, fun, rest, kind, opts)
    end
  end

  defp do_move_to_def(zipper, fun, arity, kind, opts) do
    target = Keyword.get(opts, :target)

    case Common.move_to(zipper, fn zipper ->
           case Zipper.node(zipper) do
             # Match the standard function definition
             {^kind, _, [{^fun, _, args}, _body]} when arity == :any or length(args) == arity ->
               true

             # Match a zero-arity function that is defined without parentheses
             {^kind, _, [{^fun, _, nil}, __body]} when arity == :any or arity == 0 ->
               true

             # Match a function with a guard clause
             {^kind, _, [{:when, _, [{^fun, _, args}, _guard]}, _body]}
             when arity == :any or length(args) == arity ->
               true

             # Probably not a common occurrence, but it is possible to have a
             # function with a guard clause and no args
             {^kind, _, [{:when, _, [{^fun, _, nil}, _guard]}, _body]}
             when arity == :any or arity == 0 ->
               true

             _ ->
               false
           end
         end) do
      {:ok, zipper} ->
        move_to_target(zipper, target)

      :error ->
        :error
    end
  end

  defp move_to_target(zipper, target) do
    case target do
      :inside ->
        Common.move_to_do_block(zipper)

      :before ->
        move_before_attrs(zipper)

      :at ->
        {:ok, zipper}

      _ ->
        :error
    end
  end

  defp move_before_attrs(zipper) do
    current_node = Zipper.node(zipper)

    case Common.move_left(zipper, fn z ->
           if z.path[:left] == [] || z.path[:left] == nil do
             true
           else
             !match_function_or_attr?(z, current_node)
           end
         end) do
      {:ok, zipper} = resp ->
        # We need to match here to see if we are at the leftmost node and
        # still match the function or attr. This happens when a function
        # being matched on is the first thing in the module.
        if match_function_or_attr?(zipper, current_node) do
          resp
        else
          # Otherwise, we need to move right to the function or attr
          Common.move_right(zipper, 1)
        end

      :error ->
        :error
    end
  end

  defp match_function_or_attr?(zipper, current_node) do
    case Zipper.node(zipper) do
      ^current_node ->
        true

      {:@, _, [{:doc, _, _}]} ->
        true

      {:@, _, [{:spec, _, _}]} ->
        true

      {:@, _, [{:impl, _, _}]} ->
        true

      _ ->
        false
    end
  end

  @doc "Moves to a function call by the given name and arity, matching the given predicate, in the current scope"
  @spec move_to_function_call_in_current_scope(
          Zipper.t(),
          atom | {atom, atom},
          non_neg_integer() | list(non_neg_integer()) | :any
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
  @spec move_to_function_call(
          Zipper.t(),
          atom | {atom, atom},
          :any | non_neg_integer() | list(non_neg_integer())
        ) ::
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

  def function_call?(%Zipper{} = zipper, name, arity) when is_list(arity) do
    Enum.any?(arity, &function_call?(zipper, name, &1))
  end

  def function_call?(%Zipper{} = zipper, name, arity) when is_atom(name) do
    zipper
    |> Common.maybe_move_to_single_child_block()
    |> Zipper.node()
    |> case do
      {^name, _, args} when arity == :any or length(args) == arity ->
        true

      {{^name, _, context}, _, args}
      when is_atom(context) and (arity == :any or length(args) == arity) ->
        true

      {:|>, _, [_, {{^name, _, context}, _, rest}]}
      when is_atom(context) and (arity == :any or length(rest) == arity - 1) ->
        true

      {:|>, _, [_, {^name, _, rest}]}
      when arity == :any or length(rest) == arity - 1 ->
        true

      _ ->
        false
    end
  end

  def function_call?(%Zipper{} = zipper, {module, name}, arity) when is_atom(name) do
    node =
      zipper
      |> Common.maybe_move_to_single_child_block()
      |> Zipper.node()

    function_call_shape? =
      case node do
        {{:., _, [{:__aliases__, _, _} = alias, ^name]}, _, args}
        when arity == :any or length(args) == arity ->
          Common.nodes_equal?(Zipper.replace(zipper, alias), module)

        {{:., _, [{:__aliases__, _, _} = alias, {^name, _, context}]}, _, args}
        when is_atom(context) and (arity == :any or length(args) == arity) ->
          Common.nodes_equal?(Zipper.replace(zipper, alias), module)

        {:|>, _,
         [
           _,
           {{:., _, [{:__aliases__, _, _} = alias, ^name]}, _, args}
         ]}
        when arity == :any or length(args) == arity - 1 ->
          Common.nodes_equal?(Zipper.replace(zipper, alias), module)

        {:|>, _,
         [
           _,
           {{:., _, [{:__aliases__, _, _} = alias, {^name, _, context}]}, _, args}
         ]}
        when is_atom(context) and (arity == :any or length(args) == arity - 1) ->
          Common.nodes_equal?(Zipper.replace(zipper, alias), module)

        {{:., _, [^module, ^name]}, _, args}
        when arity == :any or length(args) == arity ->
          true

        {{:., _, [^module, {^name, _, context}]}, _, args}
        when is_atom(context) and (arity == :any or length(args) == arity) ->
          true

        {:|>, _,
         [
           _,
           {{:., _, [^module, ^name]}, _, args}
         ]}
        when arity == :any or length(args) == arity - 1 ->
          true

        {:|>, _,
         [
           _,
           {{:., _, [^module, {^name, _, context}]}, _, args}
         ]}
        when is_atom(context) and (arity == :any or length(args) == arity - 1) ->
          true

        {{:., _, [{:__block__, _, [^module]}, ^name]}, _, args}
        when arity == :any or length(args) == arity ->
          true

        {{:., _, [{:__block__, _, [^module]}, {^name, _, context}]}, _, args}
        when is_atom(context) and (arity == :any or length(args) == arity) ->
          true

        {:|>, _,
         [
           _,
           {{:., _, [{:__block__, _, [^module]}, ^name]}, _, args}
         ]}
        when arity == :any or length(args) == arity - 1 ->
          true

        {:|>, _,
         [
           _,
           {{:., _, [{:__block__, _, [^module]}, {^name, _, context}]}, _, args}
         ]}
        when is_atom(context) and (arity == :any or length(args) == arity - 1) ->
          true

        {^name, _, args} when is_list(args) and (arity == :any or length(args) == arity) ->
          imported?(zipper, module, name, length(args))

        {{^name, _, context}, _, args}
        when is_atom(context) and (arity == :any or length(args) == arity) ->
          imported?(zipper, module, name, length(args))

        {:|>, _, [_, {{^name, _, context}, _, rest}]}
        when is_atom(context) and (arity == :any or length(rest) == arity - 1) ->
          imported?(zipper, module, name, length(rest) + 1)

        {:|>, _, [_, {^name, _, rest}]}
        when arity == :any or length(rest) == arity - 1 ->
          imported?(zipper, module, name, length(rest) + 1)

        _node ->
          false
      end

    if function_call_shape? do
      case Zipper.up(zipper) do
        %{node: {:&, _, _}} ->
          false

        _ ->
          true
      end
    else
      false
    end
  end

  @doc false
  def imported?(zipper, module, name, arity) do
    case Igniter.Code.Common.current_env(zipper) do
      {:ok, env} ->
        Enum.any?(env.functions ++ env.macros, fn {imported_module, funcs} ->
          imported_module == module &&
            Enum.any?(funcs, fn {imported_name, imported_arity} ->
              name == imported_name && (arity == :any || imported_arity == arity)
            end)
        end)

      _ ->
        module == Kernel
    end
  end

  @doc """
  Returns true if the value is a function literal.

  Examples:
    - `fn x -> x end`
    - `&(&1 + &2)`
    - `&SomeMod.fun/2`

  To refine the check, you can use `name` and `arity`.

  ## Names

  - `:any` - matches any function literal, named or not
  - `:any_named` - matches any named function literal
  - `:anonymous` - matches any anonymous function literal
  - `{module, name}` - matches a function literal with the given module and name
  """
  @spec function?(
          Zipper.t(),
          name :: :any | :any_named | {module(), atom()} | :anonymous,
          arity :: :any | non_neg_integer() | [non_neg_integer()]
        ) ::
          boolean
  def function?(zipper, name \\ :any, arity \\ :any)

  def function?(zipper, name, arity) when is_list(arity) do
    Enum.any?(arity, fn arity -> function?(zipper, name, arity) end)
  end

  def function?(%Zipper{}, name, _arity)
      when is_atom(name) and name not in [:any, :any_named, :anonymous] do
    raise ArgumentError,
          "The name argument must be one of `:any`, `:any_named`, `:anonymous` or a `{module, name}` tuple."
  end

  def function?(%Zipper{} = zipper, :anonymous, arity) do
    node =
      zipper
      |> Common.maybe_move_to_single_child_block()
      |> Zipper.node()

    case node do
      {:&, _, [{{:., _, [{:__aliases__, _, _}, _]}, _, _}]} ->
        false

      {:&, _, [{:&, _, _}]} ->
        arity == :any or arity == 1

      {:&, _, [{name, _, _}]} when is_atom(name) ->
        false

      {:&, _, [body]} ->
        arity == :any or count_captures(body) == arity

      {:fn, _, [{:->, _, [[{:when, _, args}], _body]} | _]}
      when arity == :any or length(args) == arity ->
        true

      {:fn, _, [{:->, _, [args, _body]} | _]} when arity == :any or length(args) == arity ->
        true

      {:fn, _, _} ->
        true

      _ ->
        false
    end
  end

  def function?(%Zipper{} = zipper, {module, name}, arity) do
    node =
      zipper
      |> Common.maybe_move_to_single_child_block()
      |> Zipper.node()

    case node do
      {:&, _, [{:/, _, [{^name, _, context}, actual_arity]}]}
      when is_atom(context) and (arity == :any or actual_arity == arity) ->
        imported?(zipper, module, name, actual_arity)

      {:&, _, [{:/, _, [{^name, _, context}, {:__block__, _, [actual_arity]}]}]}
      when is_atom(context) and (arity == :any or actual_arity == arity) ->
        imported?(zipper, module, name, actual_arity)

      {:&, _, [{:/, _, [^name, actual_arity]}]}
      when arity == :any or actual_arity == arity ->
        imported?(zipper, module, name, actual_arity)

      {:&, _, [{:/, _, [^name, {:__block__, _, [actual_arity]}]}]}
      when arity == :any or actual_arity == arity ->
        imported?(zipper, module, name, actual_arity)

      {:&, _,
       [
         {:/, _,
          [
            {{:., _, [{:__aliases__, _, _} = alias, ^name]}, _, _},
            actual_arity
          ]}
       ]}
      when arity == :any or actual_arity == arity ->
        Common.nodes_equal?(Zipper.replace(zipper, alias), module)

      {:&, _,
       [
         {:/, _,
          [
            {{:., _, [{:__aliases__, _, _} = alias, ^name]}, _, _},
            {:__block__, _, [actual_arity]}
          ]}
       ]}
      when arity == :any or actual_arity == arity ->
        Common.nodes_equal?(Zipper.replace(zipper, alias), module)

      {:&, _, [call]} ->
        case call do
          {{:., _, [{:__aliases__, _, _} = alias, ^name]}, _, args}
          when arity == :any or length(args) == arity ->
            Common.nodes_equal?(Zipper.replace(zipper, alias), module)

          {{:., _, [{:__aliases__, _, _} = alias, {^name, _, context}]}, _, args}
          when is_atom(context) and (arity == :any or length(args) == arity) ->
            Common.nodes_equal?(Zipper.replace(zipper, alias), module)

          {:|>, _,
           [
             _,
             {{:., _, [{:__aliases__, _, _} = alias, ^name]}, _, args}
           ]}
          when arity == :any or length(args) == arity - 1 ->
            Common.nodes_equal?(Zipper.replace(zipper, alias), module)

          {:|>, _,
           [
             _,
             {{:., _, [{:__aliases__, _, _} = alias, {^name, _, context}]}, _, args}
           ]}
          when is_atom(context) and (arity == :any or length(args) == arity - 1) ->
            Common.nodes_equal?(Zipper.replace(zipper, alias), module)

          {^name, _, args} when arity == :any or length(args) == arity ->
            imported?(zipper, module, name, length(args))

          {{^name, _, context}, _, args}
          when is_atom(context) and (arity == :any or length(args) == arity) ->
            imported?(zipper, module, name, length(args))

          {:|>, _, [_, {{^name, _, context}, _, rest}]}
          when is_atom(context) and (arity == :any or length(rest) == arity - 1) ->
            imported?(zipper, module, name, length(rest) + 1)

          {:|>, _, [_, {^name, _, rest}]}
          when arity == :any or length(rest) == arity - 1 ->
            imported?(zipper, module, name, length(rest) + 1)

          _ ->
            false
        end

      _ ->
        false
    end
  end

  def function?(%Zipper{} = zipper, :any, arity) do
    function?(zipper, :any_named, arity) or function?(zipper, :anonymous, arity)
  end

  def function?(%Zipper{} = zipper, :any_named, arity) do
    node =
      zipper
      |> Common.maybe_move_to_single_child_block()
      |> Zipper.node()

    case node do
      {:&, _, [{:/, _, [{name, _, context}, actual_arity]}]}
      when is_atom(name) and is_atom(context) and
             (arity == :any or actual_arity == arity) ->
        true

      {:&, _, [{:/, _, [{name, _, context}, {:__block__, _, [actual_arity]}]}]}
      when is_atom(name) and is_atom(context) and
             (arity == :any or actual_arity == arity) ->
        true

      {:&, _, [{:/, _, [name, actual_arity]}]}
      when is_atom(name) and (arity == :any or actual_arity == arity) ->
        true

      {:&, _, [{:/, _, [name, {:__block__, _, [actual_arity]}]}]}
      when is_atom(name) and (arity == :any or actual_arity == arity) ->
        true

      {:&, _,
       [
         {:/, _,
          [
            {{:., _, [{:__aliases__, _, _}, name]}, _, _},
            actual_arity
          ]}
       ]}
      when is_atom(name) and (arity == :any or actual_arity == arity) ->
        true

      {:&, _,
       [
         {:/, _,
          [
            {{:., _, [{:__aliases__, _, _}, name]}, _, _},
            {:__block__, _, [actual_arity]}
          ]}
       ]}
      when is_atom(name) and (arity == :any or actual_arity == arity) ->
        true

      {:&, _, [call]} ->
        case call do
          {{:., _, [{:__aliases__, _, _}, name]}, _, args}
          when is_atom(name) and (arity == :any or length(args) == arity) ->
            true

          {{:., _, [{:__aliases__, _, _}, {name, _, context}]}, _, args}
          when is_atom(name) and is_atom(context) and (arity == :any or length(args) == arity) ->
            true

          {:|>, _,
           [
             _,
             {{:., _, [{:__aliases__, _, _split}, name]}, _, args}
           ]}
          when is_atom(name) or (arity == :any or length(args) == arity - 1) ->
            true

          {:|>, _,
           [
             _,
             {{:., _, [{:__aliases__, _, _}, {name, _, context}]}, _, args}
           ]}
          when is_atom(name) and is_atom(context) and (arity == :any or length(args) == arity - 1) ->
            true

          {name, _, args} when is_atom(name) and (arity == :any or length(args) == arity) ->
            true

          {{name, _, context}, _, args}
          when is_atom(name) and is_atom(context) and
                 (arity == :any or length(args) == arity) ->
            true

          {:|>, _, [_, {name, _, context} | rest]}
          when is_atom(name) and is_atom(context) and (arity == :any or length(rest) == arity - 1) ->
            true

          {:|>, _, [_, name | rest]}
          when is_atom(name) and (arity == :any or length(rest) == arity - 1) ->
            true

          _ ->
            false
        end

      _ ->
        false
    end
  end

  @doc """
  Gets the name of a local function call.

  Returns `:error` if the node is not a function call or cannot be determined.
  """
  @spec get_local_function_call_name(Zipper.t()) :: {:ok, atom()} | :error
  def get_local_function_call_name(%Zipper{} = zipper) do
    case get_local_function_call(zipper) do
      {:ok, {name, _arity}} -> {:ok, name}
      :error -> :error
    end
  end

  @doc """
  Gets the name and arity of a local function call.

  Returns `:error` if the node is not a function call or cannot be determined.
  """
  @spec get_local_function_call(Zipper.t()) :: {:ok, {atom(), non_neg_integer()}} | :error
  def get_local_function_call(%Zipper{} = zipper) do
    zipper
    |> Common.maybe_move_to_single_child_block()
    |> Zipper.node()
    |> case do
      {:__block__, _, _} ->
        :error

      {:|>, _, [_, {{name, _, context}, _, args}]} when is_atom(context) and is_atom(name) ->
        {:ok, {name, length(args) + 1}}

      {:|>, _, [_, {name, _, args}]} when is_atom(name) ->
        {:ok, {name, length(args) + 1}}

      {name, _, args} when is_atom(name) ->
        {:ok, {name, length(args)}}

      {{name, _, context}, _, args} when is_atom(context) and is_atom(name) and is_list(args) ->
        {:ok, {name, length(args)}}

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

      {:|>, _, [_, {{name, _, context}, _, _}]} when is_atom(context) and is_atom(name) ->
        true

      {:|>, _, [_, {name, _, _}]} when is_atom(name) ->
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
             {:ok, Zipper.t()} | :error | term())
        ) ::
          {:ok, Zipper.t()} | :error | term()
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
                  |> Common.move_right(index)
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
            |> Common.move_right(index)
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
                  |> Common.move_right(index)
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
            |> Common.move_right(index + offset)
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
            |> Common.move_right(index + 1)
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
                |> Common.move_right(index)
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

  # Counts up all the arguments and generates new unique arguments for them.
  # Works around the caveat that each usage of a unique `&n` variable must only
  # be counted once.
  defp count_captures(args) do
    Macro.prewalk(args, [], fn
      {:&, _, [v]} = ast, acc when is_integer(v) ->
        {ast, [v | acc]}

      ast, acc ->
        {ast, acc}
    end)
    |> elem(1)
    |> Enum.uniq()
    |> Enum.count()
  end
end
