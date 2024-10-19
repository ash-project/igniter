defmodule Igniter.Refactors.Rename do
  @moduledoc "Refactors for renaming things in a project"
  alias Igniter.Code.Common
  alias Sourceror.Zipper

  @function_module_attrs [:doc, :spec, :decorate]

  @doc """
  Renames a function globally across a project.

  ## Options

  - `:arity` - `:any` | integer | [integer]. The arity or arities of the function to rename. Defaults to `:any`.
  - `:deprecate` - `:soft | :hard`. Leave the original function in place, but with a deprecation.
    Soft deprecations appear in documentation but do not cause warnings. Hard deprecations warn when they are called.
  """
  @spec rename_function(
          Igniter.t(),
          old :: {module(), atom()},
          new :: {module(), atom()},
          opts :: Keyword.t()
        ) :: Igniter.t()
  def rename_function(igniter, old, new, opts \\ [])

  def rename_function(igniter, {old_module, old_function}, {new_module, new_function}, opts) do
    Igniter.update_all_elixir_files(igniter, fn zipper ->
      Enum.reduce(List.wrap(opts[:arity]), {:ok, zipper}, fn arity, {:ok, zipper} ->
        with {:ok, zipper} <-
               remap_calls(zipper, {old_module, old_function}, {new_module, new_function}, arity),
             {:ok, zipper} <-
               remap_references(
                 zipper,
                 {old_module, old_function},
                 {new_module, new_function},
                 arity
               ) do
          {:ok, zipper}
        else
          _ ->
            {:ok, zipper}
        end
      end)
    end)
    |> remap_function_definition(
      {old_module, old_function},
      {new_module, new_function},
      opts[:arity],
      opts[:deprecate]
    )
  end

  defp remap_function_definition(
         igniter,
         {old_module, old_function},
         {new_module, new_function},
         arity,
         deprecate
       ) do
    case Igniter.Project.Module.find_module(igniter, old_module) do
      {:ok, {igniter, source, zipper}} ->
        old_zipper = zipper

        with {:ok, zipper} <-
               update_imports(zipper, old_module, new_module, old_function, new_function, arity),
             {:ok, zipper} <-
               update_refs(
                 zipper,
                 old_module,
                 new_module,
                 old_function,
                 new_function,
                 arity,
                 deprecate
               ) do
          igniter =
            write_source(igniter, source, zipper)

          if new_module == old_module do
            igniter
          else
            bodies =
              Igniter.Code.Common.find_all(old_zipper, fn zipper ->
                case subsume_module_attrs(zipper) do
                  %{node: {:def, _, [{^old_function, _, args}, _]}} ->
                    arity == :any || length(args) in List.wrap(arity)

                  _ ->
                    false
                end
              end)

            case bodies do
              [] ->
                igniter

              defs ->
                defs_as_string =
                  defs
                  |> Enum.map(& &1.node)
                  |> then(&{:__block__, [], &1})
                  |> Sourceror.to_string()

                Igniter.Project.Module.find_and_update_or_create_module(
                  igniter,
                  new_module,
                  defs_as_string,
                  fn zipper ->
                    {:ok,
                     Enum.reduce(defs, zipper, fn def, zipper ->
                       Igniter.Code.Common.add_code(zipper, Sourceror.to_string(def.node))
                     end)}
                  end
                )
            end
          end
        else
          {:error, error} ->
            Igniter.add_issue(igniter, error)

          {:warning, error} ->
            Igniter.add_warning(igniter, error)
        end

      _ ->
        igniter
    end
  end

  def subsume_module_attrs(zipper) do
    case zipper.node do
      {:@, _, [{attr, _, _}]} when attr in @function_module_attrs ->
        subsume_module_attrs(Zipper.right(zipper))

      _value ->
        zipper
    end
  end

  defp update_imports(zipper, old_module, new_module, old_function, new_function, arity) do
    Enum.reduce(List.wrap(arity), {:ok, zipper}, fn arity, {:ok, zipper} ->
      if old_module != new_module do
        # not doing this one for now
        {:ok, zipper}
      else
        Igniter.Code.Common.update_all_matches(
          zipper,
          fn zipper ->
            Igniter.Code.Function.function_call?(zipper, :import, 2) &&
              Igniter.Code.Function.argument_equals?(zipper, 0, old_module)
          end,
          fn zipper ->
            with {:ok, zipper} <-
                   replace_import_qualifier(zipper, old_function, new_function, arity, :only),
                 {:ok, zipper} <-
                   replace_import_qualifier(zipper, old_function, new_function, arity, :except) do
              {:ok, zipper}
            else
              _ ->
                {:ok, zipper}
            end
          end
        )
      end
    end)
  end

  defp replace_import_qualifier(zipper, old_function, new_function, arity, key) do
    with {:ok, zipper} <- Igniter.Code.Function.move_to_nth_argument(zipper, 1),
         {:ok, zipper} <- Igniter.Code.Keyword.get_key(zipper, key) do
      Igniter.Code.List.map(zipper, fn zipper ->
        if Igniter.Code.Tuple.tuple?(zipper) and
             Igniter.Code.Tuple.elem_equals?(zipper, 0, old_function) do
          if arity == :any || Igniter.Code.Tuple.elem_equals?(zipper, 1, arity) do
            case Igniter.Code.Tuple.tuple_elem(zipper, 1) do
              {:ok, arity} ->
                {:ok, Zipper.replace(zipper, {new_function, arity.node})}

              _ ->
                {:ok, zipper}
            end
          else
            {:ok, zipper}
          end
        else
          {:ok, zipper}
        end
      end)
    end
  end

  defp write_source(igniter, source, zipper) do
    new_source = Rewrite.Source.update(source, :quoted, Zipper.topmost_root(zipper))
    %{igniter | rewrite: Rewrite.update!(igniter.rewrite, new_source)}
  end

  defp update_refs(zipper, old_module, new_module, old_function, new_function, arity, deprecate) do
    Enum.reduce(List.wrap(arity), {:ok, zipper}, fn arity, {:ok, zipper} ->
      Igniter.Code.Common.update_all_matches(
        zipper,
        fn zipper ->
          case subsume_module_attrs(zipper) do
            %{node: {:def, _, [{^old_function, _, args}, _body]}} ->
              arity == :any || length(args) == arity

            _other ->
              false
          end
        end,
        fn zipper ->
          if !deprecate && old_module == new_module do
            case zipper.node do
              {:def, def_meta, [{^old_function, meta, args}, body]} ->
                {:ok,
                 Igniter.Code.Common.replace_code(
                   zipper,
                   {:def, def_meta, [{new_function, meta, args}, body]}
                 )}

              _ ->
                {:ok, zipper}
            end
          else
            case subsume_module_attrs(zipper) do
              %{node: {:def, _, [{^old_function, _, args}, _]}} ->
                if deprecate do
                  if has_deprecation_type?(zipper, deprecate) do
                    {:halt_depth, zipper}
                  else
                    message =
                      if new_module == old_module do
                        "Use `#{new_function}/#{Enum.count(args)}` instead."
                      else
                        "Use `Module.#{new_function}/#{Enum.count(args)}`"
                      end

                    deprecation =
                      case deprecate do
                        :hard ->
                          "@deprecated \"#{message}\""

                        :soft ->
                          "@doc deprecated: \"#{message}\""
                      end

                    {:ok, zipper} = Igniter.Code.Function.move_to_def(zipper)

                    {:ok,
                     Igniter.Code.Common.add_code(
                       zipper,
                       deprecation,
                       :before
                     )}
                  end
                else
                  {:ok, Zipper.remove(zipper)}
                end

              _ ->
                {:ok, zipper}
            end
          end
        end
      )
    end)
  end

  defp has_deprecation_type?(nil, _), do: false

  defp has_deprecation_type?(zipper, type) do
    if type == :hard do
      case zipper.node do
        {:@, _, [{:deprecated, _, _}]} ->
          true

        {:@, _, [{v, _, _}]} when is_atom(v) ->
          has_deprecation_type?(Zipper.right(zipper), type)

        _ ->
          false
      end
    else
      case zipper.node do
        {:@, _, [{:doc, _, [v]}]} when is_list(v) ->
          is_deprecation? =
            Enum.any?(v, fn
              {:deprecated, _} ->
                true

              {{:__block__, _, [:deprecated]}, _} ->
                true

              _ ->
                false
            end)

          if is_deprecation? do
            true
          else
            has_deprecation_type?(Zipper.right(zipper), type)
          end

        _ ->
          false
      end
    end
  end

  defp remap_references(zipper, {old_module, old_function}, {new_module, new_function}, arity) do
    Igniter.Code.Common.update_all_matches(
      zipper,
      fn zipper ->
        Igniter.Code.Function.function?(zipper, {old_module, old_function}, arity)
      end,
      fn zipper ->
        {:ok,
         do_remap_reference(zipper, {old_module, old_function}, {new_module, new_function}, arity)}
      end
    )
  end

  defp do_remap_reference(zipper, {old_module, old_function}, {new_module, new_function}, arity) do
    node =
      zipper
      |> Common.maybe_move_to_single_child_block()
      |> Zipper.node()

    case node do
      {:&, _, [{:/, _, [{^old_function, [], context}, actual_arity]}]}
      when is_atom(context) and (arity == :any or actual_arity == arity) ->
        if Igniter.Code.Function.imported?(zipper, old_module, old_function, actual_arity) do
          Igniter.Code.Common.replace_code(
            zipper,
            {:&, [], [{:/, [], [{new_function, [], context}, actual_arity]}]}
          )
        else
          {:ok, zipper}
        end

      {:&, _, [{:/, _, [{^old_function, _, context}, {:__block__, _, [actual_arity]}]}]}
      when is_atom(context) and (arity == :any or actual_arity == arity) ->
        if Igniter.Code.Function.imported?(zipper, old_module, old_function, actual_arity) do
          Igniter.Code.Common.replace_code(
            zipper,
            {:&, [], [{:/, [], [{new_function, [], context}, {:__block__, [], [actual_arity]}]}]}
          )
        else
          {:ok, zipper}
        end

      {:&, _, [{:/, _, [^old_function, actual_arity]}]}
      when arity == :any or actual_arity == arity ->
        if Igniter.Code.Function.imported?(zipper, old_module, old_function, actual_arity) do
          Igniter.Code.Common.replace_code(
            zipper,
            {:&, [], [{:/, [], [new_function, actual_arity]}]}
          )
        else
          {:ok, zipper}
        end

      {:&, _, [{:/, _, [^old_function, {:__block__, _, [actual_arity]}]}]}
      when arity == :any or actual_arity == arity ->
        if Igniter.Code.Function.imported?(zipper, old_module, old_function, actual_arity) do
          Igniter.Code.Common.replace_code(
            zipper,
            {:&, [], [{:/, [], [new_function, {:__block__, [], [actual_arity]}]}]}
          )
        else
          {:ok, zipper}
        end

      {:&, _,
       [
         {:/, _,
          [
            {{:., _, [{:__aliases__, _, _} = alias, ^old_function]}, _, args},
            actual_arity
          ]}
       ]}
      when arity == :any or actual_arity == arity ->
        if Igniter.Code.Common.nodes_equal?(Zipper.replace(zipper, alias), old_module) do
          Igniter.Code.Common.replace_code(
            zipper,
            {:&, [],
             [
               {:/, [],
                [
                  {{:., [], [{:__aliases__, [], split_and_atomize(new_module)}, new_function]},
                   [], args},
                  actual_arity
                ]}
             ]}
          )
        else
          {:ok, zipper}
        end

      {:&, _,
       [
         {:/, _,
          [
            {{:., _, [{:__aliases__, _, _} = alias, ^old_function]}, _, args},
            {:__block__, _, [actual_arity]}
          ]}
       ]}
      when arity == :any or actual_arity == arity ->
        if Igniter.Code.Common.nodes_equal?(Zipper.replace(zipper, alias), old_module) do
          Igniter.Code.Common.replace_code(
            zipper,
            {:&, [],
             [
               {:/, [],
                [
                  {{:., [], [{:__aliases__, [], split_and_atomize(new_module)}, new_function]},
                   [], args},
                  {:__block__, [], [actual_arity]}
                ]}
             ]}
          )
        else
          {:ok, zipper}
        end

      {:&, _, [call]} ->
        case call do
          {{:., _, [{:__aliases__, _, _} = alias, ^old_function]}, _, args}
          when arity == :any or length(args) == arity ->
            if Igniter.Code.Common.nodes_equal?(Zipper.replace(zipper, alias), old_module) do
              Igniter.Code.Common.replace_code(
                zipper,
                {:&, [],
                 [
                   {{:., [], [{:__aliases__, [], split_and_atomize(new_module)}, new_function]},
                    [], args}
                 ]}
              )
            else
              {:ok, zipper}
            end

          {{:., _, [{:__aliases__, _, _} = alias, {^old_function, _, context}]}, _, args}
          when is_atom(context) and (arity == :any or length(args) == arity) ->
            if Igniter.Code.Common.nodes_equal?(Zipper.replace(zipper, alias), old_module) do
              Igniter.Code.Common.replace_code(
                zipper,
                {:&, [],
                 [
                   {{:., [],
                     [
                       {:__aliases__, [], split_and_atomize(new_module)},
                       {new_function, [], context}
                     ]}, [], args}
                 ]}
              )
            else
              {:ok, zipper}
            end

          {:|>, _,
           [
             first,
             {{:., _, [{:__aliases__, _, _} = alias, ^old_function]}, _, args}
           ]}
          when arity == :any or length(args) == arity - 1 ->
            if Igniter.Code.Common.nodes_equal?(Zipper.replace(zipper, alias), old_module) do
              Igniter.Code.Common.replace_code(
                zipper,
                {:&, [],
                 [
                   {:|>, [],
                    [
                      first,
                      {{:., [],
                        [{:__aliases__, [], split_and_atomize(new_module)}, new_function]}, [],
                       args}
                    ]}
                 ]}
              )
            else
              {:ok, zipper}
            end

          {:|>, _,
           [
             first,
             {{:., _, [{:__aliases__, _, _} = alias, {^old_function, _, context}]}, _, args}
           ]}
          when is_atom(context) and (arity == :any or length(args) == arity - 1) ->
            if Igniter.Code.Common.nodes_equal?(Zipper.replace(zipper, alias), old_module) do
              Igniter.Code.Common.replace_code(
                zipper,
                {:&, [],
                 [
                   {:|>, [],
                    [
                      first,
                      {{:., [],
                        [
                          {:__aliases__, [], split_and_atomize(new_module)},
                          {new_function, [], context}
                        ]}, [], args}
                    ]}
                 ]}
              )
            else
              {:ok, zipper}
            end

          {^old_function, _, args} when arity == :any or length(args) == arity ->
            if Igniter.Code.Function.imported?(zipper, old_module, old_function, length(args)) do
              Igniter.Code.Common.replace_code(
                zipper,
                {:&, [], [{new_function, [], args}]}
              )
            else
              {:ok, zipper}
            end

          {{^old_function, _, context}, _, args}
          when is_atom(context) and (arity == :any or length(args) == arity) ->
            if Igniter.Code.Function.imported?(zipper, old_module, old_function, length(args)) do
              Igniter.Code.Common.replace_code(
                zipper,
                {:&, [], [{{new_function, [], context}, [], args}]}
              )
            else
              {:ok, zipper}
            end

          {:|>, _, [first, {^old_function, _, context} | rest]}
          when is_atom(context) and (arity == :any or length(rest) == arity - 1) ->
            if Igniter.Code.Function.imported?(zipper, old_module, old_function, length(rest) + 1) do
              Igniter.Code.Common.replace_code(
                zipper,
                {:&, [],
                 [
                   {:|>, [], [first, {new_function, [], context} | rest]}
                 ]}
              )
            else
              {:ok, zipper}
            end

          {:|>, _, [first, ^old_function | rest]}
          when arity == :any or length(rest) == arity - 1 ->
            if Igniter.Code.Function.imported?(zipper, old_module, old_function, length(rest) + 1) do
              Igniter.Code.Common.replace_code(
                zipper,
                {:&, [],
                 [
                   {:|>, [], [first, new_function | rest]}
                 ]}
              )
            else
              {:ok, zipper}
            end

          _ ->
            false
        end

      _ ->
        false
    end
  end

  defp remap_calls(zipper, {old_module, old_function}, {new_module, new_function}, arity) do
    Igniter.Code.Common.update_all_matches(
      zipper,
      fn zipper ->
        Igniter.Code.Function.function_call?(zipper, {old_module, old_function}, arity)
      end,
      fn zipper ->
        {:ok, do_rename(zipper, {old_module, old_function}, {new_module, new_function}, arity)}
      end
    )
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
                  (arity == :any || imported_arity == arity)
              end)
          end)

        _ ->
          false
      end

    case node do
      {{:., dot_meta, [{:__aliases__, alias_meta, ^split}, ^old_function]}, call_meta, args} ->
        Igniter.Code.Common.replace_code(
          zipper,
          {{:., dot_meta,
            [{:__aliases__, alias_meta, split_and_atomize(new_module)}, new_function]}, call_meta,
           args}
        )

      {{:., dot_meta, [{:__aliases__, alias_meta, ^split}, {^old_function, fun_meta, context}]},
       call_meta, args}
      when is_atom(context) ->
        Igniter.Code.Common.replace_code(
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
        Igniter.Code.Common.replace_code(
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
        Igniter.Code.Common.replace_code(
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

      {^old_function, _, args} when imported? and (arity == :any or length(args) == arity) ->
        if new_module == old_module do
          Igniter.Code.Common.replace_code(zipper, {new_function, [], args})
        else
          Igniter.Code.Common.replace_code(
            zipper,
            {{:., [], [{:__aliases__, [], split_and_atomize(new_module)}, new_function]}, [],
             args}
          )
        end

      {{^old_function, _, context}, _, args}
      when is_atom(context) and imported? and (arity == :any or length(args) == arity) ->
        if new_module == old_module do
          Igniter.Code.Common.replace_code(
            zipper,
            {{new_function, [], context}, [], args}
          )
        else
          Igniter.Code.Common.replace_code(
            zipper,
            {{:., [],
              [{:__aliases__, [], split_and_atomize(new_module)}, {new_function, [], context}]},
             [], args}
          )
        end

      {:|>, _, [first_arg, {{^old_function, _, context}, _, rest}]}
      when is_atom(context) and imported? and (arity == :any or length(rest) == arity - 1) ->
        if new_module == old_module do
          Igniter.Code.Common.replace_code(
            zipper,
            {:|>, [], [first_arg, {{new_function, [], context}, [], rest}]}
          )
        else
          Igniter.Code.Common.replace_code(
            zipper,
            {:|>, [],
             [
               first_arg,
               {{:., [],
                 [
                   {:__aliases__, [], split_and_atomize(new_module)},
                   {new_function, [], context}
                 ]}, [], rest}
             ]}
          )
        end

      {:|>, _, [first_arg, ^old_function | rest]}
      when imported? and (arity == :any or length(rest) == arity - 1) ->
        if new_module == old_module do
          Igniter.Code.Common.replace_code(
            zipper,
            {:|>, [],
             [
               first_arg,
               new_function | rest
             ]}
          )
        else
          Igniter.Code.Common.replace_code(
            zipper,
            {:|>, [],
             [
               first_arg,
               {{:., [], [{:__aliases__, [], split_and_atomize(new_module)}, new_function]}, [],
                rest}
             ]}
          )
        end

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
