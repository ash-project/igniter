defmodule Igniter.Refactors.Rename do
  alias Igniter.Code.Common
  alias Sourceror.Zipper

  @spec rename_function(
          Igniter.t(),
          old :: {module(), atom()},
          new :: {module(), atom()},
          arity_or_arities :: integer | [integer] | :any
        ) :: Igniter.t()
  def rename_function(igniter, old, new, arity \\ :any)

  def rename_function(igniter, old, new, arities)
      when is_list(arities) do
    Enum.reduce(arities, igniter, fn arity, igniter ->
      rename_function(igniter, old, new, arity)
    end)
  end

  def rename_function(igniter, {old_module, old_function}, {new_module, new_function}, arity)
      when is_integer(arity) do
    Igniter.update_glob(igniter, "lib/example.ex", fn zipper ->
      Igniter.Code.Common.update_all_matches(
        zipper,
        fn zipper ->
          Igniter.Code.Function.function_call?(zipper, {old_module, old_function}, arity)
        end,
        fn zipper ->
          {:ok, do_rename(zipper, {old_module, old_function}, {new_module, new_function}, arity)}
        end
      )
    end)
  end

  defp do_rename(zipper, {old_module, old_function}, {new_module, new_function}, arity) do
    node =
      zipper
      |> Common.maybe_move_to_single_child_block()
      |> Igniter.Code.Common.expand_aliases()
      |> Zipper.node()

    split = old_module |> Module.split() |> Enum.map(&String.to_atom/1)

    imported? =
      case Igniter.Code.Common.current_env(zipper) do
        {:ok, env} ->
          Enum.any?(env.functions ++ env.macros, fn {imported_module, funcs} ->
            imported_module == old_module &&
              Enum.any?(funcs, fn {imported_name, imported_arity} ->
                old_function == imported_name &&
                  (arity == :any || Enum.count(imported_arity) == arity)
              end)
          end)

        _ ->
          false
      end

    case node do
      {{:., dot_meta, [{:__aliases__, alias_meta, ^split}, ^old_function]}, call_meta, args} ->
        Zipper.replace(
          zipper,
          {{:., dot_meta,
            [{:__aliases__, alias_meta, split_and_atomize(new_module)}, new_function]}, call_meta,
           args}
        )

      {{:., dot_meta, [{:__aliases__, alias_meta, ^split}, {^old_function, fun_meta, context}]},
       call_meta, args}
      when is_atom(context) ->
        Zipper.replace(
          zipper,
          {{:., dot_meta,
            [
              {:__aliases__, alias_meta, split_and_atomize(new_module)},
              {new_function, fun_meta, context}
            ]}, call_meta, args}
        )

      {:|>, pipe_meta,
       [
         first_arg,
         {{:., dot_meta, [{:__aliases__, alias_meta, ^split}, ^old_function]}, call_meta, args}
       ]} ->
        Zipper.replace(
          zipper,
          {:|>, pipe_meta,
           [
             first_arg,
             {{:., dot_meta,
               [{:__aliases__, alias_meta, split_and_atomize(new_module)}, new_function]},
              call_meta, args}
           ]}
        )

      {:|>, pipe_meta,
       [
         first_arg,
         {{:., dot_meta,
           [{:__aliases__, alias_meta, ^split}, {^old_function, fun_meta, context}]}, call_meta,
          args}
       ]}
      when is_atom(context) ->
        Zipper.replace(
          zipper,
          {:|>, pipe_meta,
           [
             first_arg,
             {{:., dot_meta,
               [
                 {:__aliases__, alias_meta, split_and_atomize(new_module)},
                 {new_function, fun_meta, context}
               ]}, call_meta, args}
           ]}
        )

      # {^old_function, _, args} when imported? >
      #   (arity == :any || Enum.count(args) == arity)

      # {{^old_function, _, context}, _, args} when is_atom(context) and imported? ->
      #   imported? && (arity == :any || Enum.count(args) == arity)

      # {:|>, _, [{^old_function, _, context} | rest]} when is_atom(context) and imported? ->
      #   imported? && (arity == :any || Enum.count(rest) == arity - 1)

      # {:|>, _, [^old_function | rest]} and imported? ->
      #   imported? && (arity == :any || Enum.count(rest) == arity - 1)

      _ ->
        zipper
    end
  end

  defp split_and_atomize(value) do
    value
    |> Module.split()
    |> Enum.map(&String.to_atom/1)
  end
end
