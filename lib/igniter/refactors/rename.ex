# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Igniter.Refactors.Rename do
  @moduledoc "Refactors for renaming things in a project"
  alias Igniter.Code.Common
  alias Sourceror.Zipper

  @function_module_attrs [:doc, :spec, :decorate]

  @doc """
  Renames a module globally across a project.

  Renames the module everywhere it appears: `defmodule`, `alias`, `use`,
  `import`, `require`, and all call sites. Also handles submodules, the
  corresponding test module, string literals mentioning the module name, and
  moves the file(s) to match the new module's proper location.

  ## Alias handling

  - `alias Foo.Bar` — the alias declaration and all `Bar.*` call sites are renamed.
  - `alias Foo.{Bar, Other}` — the declaration and call sites are renamed.
    Spitfire does not macro-expand the brace form, so resolution falls back to
    an explicit AST scan.
  - `alias Foo.Bar, as: B` — only the declaration is updated (`alias Foo.Baz, as: B`).
    `B.*` call sites are left untouched because the `as:` clause still resolves correctly.

  ## Limitations

  - Dynamic references (e.g. `apply/3`, `Module.concat/2` with variables) are not rewritten.
  - String-literal replacement is a plain substring replace over the raw file content,
    so it also rewrites occurrences in comments and unrelated strings. Grep after.
  """
  @spec rename_module(Igniter.t(), module(), module(), Keyword.t()) :: Igniter.t()
  def rename_module(igniter, old_module, new_module, _opts \\ [])
      when is_atom(old_module) and is_atom(new_module) do
    old_parts = Module.split(old_module)
    new_parts = Module.split(new_module)

    old_aliases = Enum.map(old_parts, &String.to_atom/1)
    new_aliases = Enum.map(new_parts, &String.to_atom/1)

    old_test_aliases =
      List.update_at(old_parts, -1, &(&1 <> "Test")) |> Enum.map(&String.to_atom/1)

    new_test_aliases =
      List.update_at(new_parts, -1, &(&1 <> "Test")) |> Enum.map(&String.to_atom/1)

    old_short = [List.last(old_aliases)]
    new_short = [List.last(new_aliases)]

    old_module_str = Enum.join(old_parts, ".")
    new_module_str = Enum.join(new_parts, ".")

    renames = [
      {old_aliases, new_aliases},
      {old_test_aliases, new_test_aliases}
    ]

    igniter = Igniter.include_all_elixir_files(igniter)

    {old_path, igniter} =
      case Igniter.Project.Module.find_module(igniter, old_module) do
        {:ok, {igniter, source, _zipper}} ->
          {Rewrite.Source.get(source, :path), igniter}

        {:error, igniter} ->
          {Igniter.Project.Module.proper_location(igniter, old_module), igniter}
      end

    new_path = Igniter.Project.Module.proper_location(igniter, new_module)
    affected_files = find_affected_files(igniter, old_module_str, old_aliases, old_short)

    igniter
    |> rewrite_affected_files(
      affected_files,
      renames,
      old_aliases,
      old_short,
      new_short,
      old_module_str,
      new_module_str
    )
    |> move_submodule_files(old_path, new_path)
    |> move_module_file(old_path, new_path)
  end

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
    opts = Keyword.put(opts, :arity, opts[:arity] || :any)

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
              old_zipper
              |> Igniter.Code.Common.find_all(fn zipper ->
                case subsume_module_attrs(zipper, [], not_if_above?: true) do
                  {%{node: {:def, _, [{^old_function, _, args}, _]}}, _} ->
                    arity == :any || length(args) in List.wrap(arity)

                  _ ->
                    false
                end
              end)
              |> Enum.map(fn zipper ->
                Zipper.traverse(zipper, fn
                  %{node: {:@, _, [{:spec, _, _}]} = node} = zipper ->
                    Zipper.replace(
                      zipper,
                      rename_spec(node, old_function, new_function)
                    )

                  %{node: {:def, def_meta, [{^old_function, fun_meta, args}, body]}} = zipper ->
                    Zipper.replace(
                      zipper,
                      {:def, def_meta, [{new_function, fun_meta, args}, body]}
                    )

                  zipper ->
                    zipper
                end)
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

  def subsume_module_attrs(zipper, attrs \\ [], top? \\ true) do
    continue? =
      if top? do
        case Zipper.up(zipper) do
          %{node: {:@, _, [{attr, _, _}]}} when attr in @function_module_attrs ->
            false

          _ ->
            true
        end
      else
        true
      end

    if continue? do
      case zipper.node do
        {:@, _, [{attr, _, _}]} = node when attr in @function_module_attrs ->
          subsume_module_attrs(
            Zipper.right(zipper),
            [node | attrs],
            false
          )

        _ ->
          {zipper, attrs}
      end
    else
      {zipper, attrs}
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
    new_source = Igniter.update_source(source, igniter, :quoted, Zipper.topmost_root(zipper))
    %{igniter | rewrite: Rewrite.update!(igniter.rewrite, new_source)}
  end

  defp update_refs(zipper, old_module, new_module, old_function, new_function, arity, deprecate) do
    Enum.reduce(List.wrap(arity), {:ok, zipper}, fn arity, {:ok, zipper} ->
      Igniter.Code.Common.update_all_matches(
        zipper,
        fn zipper ->
          case subsume_module_attrs(zipper) do
            {%{node: {:def, _, [{^old_function, _, args}, _body]}}, _} ->
              arity == :any || length(args) == arity

            _other ->
              false
          end
        end,
        fn zipper ->
          if !deprecate && old_module == new_module do
            case subsume_module_attrs(zipper) do
              {%{node: {:def, def_meta, [{^old_function, meta, args}, body]} = node}, attrs} ->
                {:halt_depth,
                 zipper
                 |> remove_until(node)
                 |> Zipper.replace({:def, def_meta, [{new_function, meta, args}, body]})
                 |> prepend_attrs(attrs, old_function, new_function)}

              other ->
                other
            end
          else
            case subsume_module_attrs(zipper) do
              {%{node: {:def, def_meta, [{^old_function, meta, args}, body]}}, attrs} ->
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

                    Igniter.Code.Common.add_code(
                      zipper,
                      deprecation,
                      placement: :before
                    )
                    |> then(fn zipper ->
                      if new_module == old_module do
                        Igniter.Code.Common.add_code(
                          zipper,
                          {:def, def_meta, [{new_function, meta, args}, body]},
                          placement: :before
                        )
                        |> prepend_attrs(attrs, old_function, new_function)
                      else
                        zipper
                      end
                    end)
                    |> then(&{:halt_depth, &1})
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

  defp remove_until(zipper, node) do
    if zipper.node == node do
      zipper
    else
      zipper
      |> Zipper.remove()
      |> Zipper.next()
      |> case do
        nil ->
          zipper

        next ->
          remove_until(next, node)
      end
    end
  end

  defp prepend_attrs(zipper, attrs, old_function, new_function) do
    Enum.reduce(attrs, zipper, fn attr, zipper ->
      attr = rename_spec(attr, old_function, new_function)

      Igniter.Code.Common.add_code(zipper, attr, placement: :before)
    end)
  end

  defp rename_spec(attr, old_function, new_function) do
    case attr do
      {:@, at_meta,
       [
         {:spec, spec_meta,
          [
            {:"::", returns_meta, [{^old_function, name_meta, args}, returns]}
          ]}
       ]} ->
        {:@, at_meta,
         [
           {:spec, spec_meta,
            [
              {:"::", returns_meta, [{new_function, name_meta, args}, returns]}
            ]}
         ]}

      other ->
        other
    end
  end

  defp has_deprecation_type?(nil, _), do: false

  defp has_deprecation_type?(zipper, type) do
    if type == :hard do
      case zipper.node do
        {:@, _, [{:deprecated, _, _}]} ->
          true

        {:@, _, [{v, _, _}]} when is_atom(v) ->
          has_deprecation_type?(Zipper.right(zipper), type)

        _node ->
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

  @doc false
  def do_remap_reference(zipper, {old_module, old_function}, {new_module, new_function}, arity) do
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

          {:|>, _, [first, {{^old_function, _, context}, _, rest}]}
          when is_atom(context) and (arity == :any or length(rest) == arity - 1) ->
            if Igniter.Code.Function.imported?(zipper, old_module, old_function, length(rest) + 1) do
              Igniter.Code.Common.replace_code(
                zipper,
                {:&, [],
                 [
                   {:|>, [], [first, {{new_function, [], context}, [], rest}]}
                 ]}
              )
            else
              {:ok, zipper}
            end

          {:|>, _, [first, {^old_function, _, rest}]}
          when arity == :any or length(rest) == arity - 1 ->
            if Igniter.Code.Function.imported?(zipper, old_module, old_function, length(rest) + 1) do
              Igniter.Code.Common.replace_code(
                zipper,
                {:&, [],
                 [
                   {:|>, [], [first, {new_function, [], rest}]}
                 ]}
              )
            else
              {:ok, zipper}
            end

          _ ->
            :error
        end

      _ ->
        :error
    end
  end

  defp remap_calls(zipper, {old_module, old_function}, {new_module, new_function}, arity) do
    Igniter.Code.Common.update_all_matches(
      zipper,
      fn zipper ->
        Igniter.Code.Function.function_call?(zipper, {old_module, old_function}, arity)
      end,
      fn zipper ->
        do_rename(zipper, {old_module, old_function}, {new_module, new_function}, arity)
      end
    )
  end

  @doc false
  def do_rename(zipper, {old_module, old_function}, {new_module, new_function}, arity) do
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
        {:ok,
         Igniter.Code.Common.replace_code(
           zipper,
           {{:., dot_meta,
             [{:__aliases__, alias_meta, split_and_atomize(new_module)}, new_function]},
            call_meta, args}
         )}

      {{:., dot_meta, [{:__aliases__, alias_meta, ^split}, {^old_function, fun_meta, context}]},
       call_meta, args}
      when is_atom(context) ->
        {:ok,
         Igniter.Code.Common.replace_code(
           zipper,
           {{:., dot_meta,
             [
               {:__aliases__, alias_meta, split_and_atomize(new_module)},
               {new_function, fun_meta, context}
             ]}, call_meta, args}
         )}

      {:|>, pipe_meta,
       [
         first_arg,
         {{:., dot_meta, [{:__aliases__, alias_meta, ^split}, ^old_function]}, call_meta, args}
       ]} ->
        {:ok,
         Igniter.Code.Common.replace_code(
           zipper,
           {:|>, pipe_meta,
            [
              first_arg,
              {{:., dot_meta,
                [{:__aliases__, alias_meta, split_and_atomize(new_module)}, new_function]},
               call_meta, args}
            ]}
         )}

      {:|>, pipe_meta,
       [
         first_arg,
         {{:., dot_meta,
           [{:__aliases__, alias_meta, ^split}, {^old_function, fun_meta, context}]}, call_meta,
          args}
       ]}
      when is_atom(context) ->
        {:ok,
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
         )}

      {^old_function, meta, args} when imported? and (arity == :any or length(args) == arity) ->
        if new_module == old_module do
          {:ok, Zipper.replace(zipper, {new_function, meta, args})}
        else
          {:ok,
           Igniter.Code.Common.replace_code(
             zipper,
             {{:., [], [{:__aliases__, [], split_and_atomize(new_module)}, new_function]}, meta,
              args}
           )}
        end

      {{^old_function, ref_meta, context}, meta, args}
      when is_atom(context) and imported? and (arity == :any or length(args) == arity) ->
        if new_module == old_module do
          {:ok,
           Igniter.Code.Common.replace_code(
             zipper,
             {{new_function, ref_meta, context}, meta, args}
           )}
        else
          {:ok,
           Igniter.Code.Common.replace_code(
             zipper,
             {{:., [],
               [
                 {:__aliases__, [], split_and_atomize(new_module)},
                 {new_function, ref_meta, context}
               ]}, meta, args}
           )}
        end

      {:|>, pipe_meta, [first_arg, {{^old_function, ref_meta, context}, meta, rest}]}
      when is_atom(context) and imported? and (arity == :any or length(rest) == arity - 1) ->
        if new_module == old_module do
          {:ok,
           Igniter.Code.Common.replace_code(
             zipper,
             {:|>, pipe_meta, [first_arg, {{new_function, ref_meta, context}, meta, rest}]}
           )}
        else
          {:ok,
           Igniter.Code.Common.replace_code(
             zipper,
             {:|>, pipe_meta,
              [
                first_arg,
                {{:., [],
                  [
                    {:__aliases__, [], split_and_atomize(new_module)},
                    {new_function, ref_meta, context}
                  ]}, meta, rest}
              ]}
           )}
        end

      {:|>, pipe_meta, [first_arg, {^old_function, _, rest}]}
      when imported? and (arity == :any or length(rest) == arity - 1) ->
        if new_module == old_module do
          {:ok,
           Igniter.Code.Common.replace_code(
             zipper,
             {:|>, pipe_meta,
              [
                first_arg,
                {new_function, [], rest}
              ]}
           )}
        else
          {:ok,
           Igniter.Code.Common.replace_code(
             zipper,
             {:|>, pipe_meta,
              [
                first_arg,
                {{:., [], [{:__aliases__, [], split_and_atomize(new_module)}, new_function]}, [],
                 rest}
              ]}
           )}
        end

      _ ->
        {:ok, zipper}
    end
  end

  defp split_and_atomize(value) do
    value
    |> Module.split()
    |> Enum.map(&String.to_atom/1)
  end

  ## rename_module helpers

  # Substring check catches most references; AST fallback catches
  # `alias Ns.{..., Short, ...}` where the full name never appears literally.
  defp find_affected_files(igniter, old_module_str, old_aliases, old_short) do
    namespace_segs = Enum.drop(old_aliases, -1)
    multi_alias_prefix = Enum.join(namespace_segs, ".") <> ".{"

    igniter.rewrite
    |> Rewrite.sources()
    |> Enum.filter(fn source ->
      path = Rewrite.Source.get(source, :path)
      content = Rewrite.Source.get(source, :content)

      String.ends_with?(path, [".ex", ".exs"]) &&
        (String.contains?(content, old_module_str) ||
           (namespace_segs != [] && String.contains?(content, multi_alias_prefix) &&
              source
              |> Rewrite.Source.get(:quoted)
              |> Zipper.zip()
              |> has_multi_alias_for?(namespace_segs, old_short)))
    end)
    |> Enum.map(&Rewrite.Source.get(&1, :path))
  end

  defp rewrite_affected_files(
         igniter,
         files,
         renames,
         old_aliases,
         old_short,
         new_short,
         old_str,
         new_str
       ) do
    Enum.reduce(files, igniter, fn path, igniter ->
      # String replace must run before the AST pass, or "Example" inside
      # a freshly-rendered "NewExample" gets replaced again → "NewNewExample".
      igniter
      |> replace_module_strings_in_file(path, old_str, new_str)
      |> Igniter.update_elixir_file(path, fn zipper ->
        zipper
        |> rename_aliased_short_forms(old_aliases, old_short, new_short)
        |> apply_module_renames(renames)
        |> then(&{:ok, &1})
      end)
    end)
  end

  # Renames short-form call sites that resolve via `alias Foo.Bar` (plain or
  # multi-alias). `alias Foo.Bar, as: B` is intentionally left alone — the
  # as: clause keeps resolving after apply_module_renames updates the target.
  defp rename_aliased_short_forms(zipper, old_aliases, old_short, new_short) do
    namespace_segs = Enum.drop(old_aliases, -1)
    has_multi = has_multi_alias_for?(Zipper.top(zipper), namespace_segs, old_short)

    case Common.update_all_matches(
           zipper,
           fn
             %Zipper{node: {:__aliases__, _, ^old_short}} = z ->
               case Common.expand_alias(z) |> Zipper.node() do
                 {:__aliases__, _, ^old_aliases} ->
                   true

                 _ ->
                   has_multi
               end

             _ ->
               false
           end,
           fn %Zipper{node: {:__aliases__, meta, _}} = z ->
             {:ok, Zipper.replace(z, {:__aliases__, meta, new_short})}
           end
         ) do
      {:ok, updated} -> updated
      _ -> zipper
    end
  end

  # Matches `alias <namespace_segs>.{..., <old_short>, ...}`.
  defp has_multi_alias_for?(zipper, namespace_segs, old_short) do
    Zipper.find(zipper, fn
      {:alias, _, [{{:., _, [{:__aliases__, _, ^namespace_segs}, :{}]}, _, short_nodes}]} ->
        Enum.any?(short_nodes, fn
          {:__aliases__, _, ^old_short} -> true
          _ -> false
        end)

      _ ->
        false
    end) != nil
  end

  defp apply_module_renames(zipper, renames) do
    Enum.reduce(renames, zipper, fn {old_aliases, new_aliases}, zipper ->
      case Common.update_all_matches(
             zipper,
             fn %Zipper{node: node} -> module_aliases_node_matches?(node, old_aliases) end,
             fn %Zipper{node: {:__aliases__, meta, aliases}} = z ->
               {:ok,
                Zipper.replace(
                  z,
                  {:__aliases__, meta, replace_module_prefix(aliases, old_aliases, new_aliases)}
                )}
             end
           ) do
        {:ok, updated} -> updated
        _ -> zipper
      end
    end)
  end

  defp replace_module_strings_in_file(igniter, path, old_str, new_str) do
    Igniter.update_file(igniter, path, fn source ->
      Rewrite.Source.update(source, :content, fn content ->
        String.replace(content, old_str, new_str)
      end)
    end)
  end

  defp move_submodule_files(igniter, old_path, new_path) do
    old_dir = Path.rootname(old_path) <> "/"
    new_dir = Path.rootname(new_path) <> "/"

    igniter.rewrite
    |> Rewrite.sources()
    |> Enum.map(&Rewrite.Source.get(&1, :path))
    |> Enum.filter(&String.starts_with?(&1, old_dir))
    |> Enum.reduce(igniter, fn sub_path, igniter ->
      new_sub_path = new_dir <> String.trim_leading(sub_path, old_dir)
      move_module_file(igniter, sub_path, new_sub_path)
    end)
  end

  defp move_module_file(igniter, same, same), do: igniter

  defp move_module_file(igniter, old_path, new_path) do
    case Rewrite.source(igniter.rewrite, old_path) do
      {:ok, _} -> Igniter.move_file(igniter, old_path, new_path)
      {:error, _} -> igniter
    end
  end

  defp module_aliases_node_matches?({:__aliases__, _meta, aliases}, target_aliases) do
    List.starts_with?(aliases, target_aliases)
  end

  defp module_aliases_node_matches?(_, _), do: false

  defp replace_module_prefix(aliases, old_prefix, new_prefix) do
    new_prefix ++ Enum.drop(aliases, length(old_prefix))
  end
end
