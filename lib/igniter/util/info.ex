# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule Igniter.Util.Info do
  @moduledoc false

  # This is an *extremely* unfortunate hack.
  # For dependencies that depend on other common dev dependencies (like `sourceror`)
  # our installation process has an issue. Specifically, we first install the dep
  # into all environments, and then set it to the right env.
  # This causes our conflict resolution logic to set the dependents (like `sourceror`)
  # to be for all envs, but then never set back to only specific envs.
  # I don't have time to fix this right now, nor can I think of a good way to actually
  # do it. So for now, this ridiculous hack will have to do :)
  @known_only_options [
    smokestack: [:test],
    mishka_chelekom: [:dev],
    mneme: [:dev, :test],
    usage_rules: [:dev],
    git_ops: [:dev],
    live_debugger: [:dev],
    tidewave: [:dev]
  ]

  @known_only_keys Keyword.keys(@known_only_options)

  require Logger
  alias Igniter.Mix.Task.Info

  def compose_install_and_validate!(
        igniter \\ Igniter.new(),
        argv,
        schema,
        task_name,
        opts,
        return \\ :options,
        insert_before \\ nil,
        acc \\ []
      ) do
    schema = %{
      schema
      | flag_conflicts: flag_groups(schema, task_name),
        alias_conflicts: alias_groups(schema, task_name)
    }

    schema = recursively_compose_schema(schema, argv, task_name, opts)

    case schema.installs do
      [] ->
        names = Enum.map_join(List.wrap(schema.adds_deps), ", ", &elem(&1, 0))

        igniter =
          igniter
          |> add_deps(
            List.wrap(schema.adds_deps),
            opts
          )
          |> Igniter.apply_and_fetch_dependencies(
            Keyword.put(opts, :operation, "compiling #{names}")
          )

        if return == :options do
          raise_on_conflicts!(schema, argv)

          {igniter, Enum.uniq(acc), validate!(argv, schema, task_name)}
        else
          {igniter, acc, schema}
        end

      installs ->
        schema = %{schema | installs: []}
        install_names = Enum.map(installs, &elem(&1, 0))

        count = Enum.count(install_names)

        names_message =
          if count >= 4 do
            "#{count} packages"
          else
            Enum.join(
              Enum.uniq(Enum.map(List.wrap(schema.adds_deps), &elem(&1, 0)) ++ install_names),
              ", "
            )
          end

        installs =
          Enum.map(installs, fn
            {dep, val} when is_binary(val) ->
              if dep in @known_only_keys || opts[:only] do
                {dep, val, only: opts[:only] || @known_only_options[dep]}
              else
                {dep, val}
              end

            {dep, dep_opts} when is_list(dep_opts) ->
              if dep in @known_only_keys || opts[:only] do
                if opts[:only] do
                  {dep, Keyword.put(dep_opts, :only, opts[:only])}
                else
                  {dep, Keyword.put_new(dep_opts, :only, @known_only_options[dep])}
                end
              else
                {dep, dep_opts}
              end

            {dep, val, dep_opts} when dep in @known_only_keys ->
              if dep in @known_only_keys || opts[:only] do
                if opts[:only] do
                  {dep, val, Keyword.put(dep_opts, :only, opts[:only])}
                else
                  {dep, val, Keyword.put_new(dep_opts, :only, @known_only_options[dep])}
                end
              else
                {dep, val, dep_opts}
              end

            other ->
              other
          end)

        igniter =
          igniter
          |> add_deps(
            List.wrap(installs),
            opts
          )
          |> Igniter.apply_and_fetch_dependencies(
            Keyword.put(opts, :operation, "compiling #{names_message}")
          )
          |> maybe_set_dep_options(install_names, argv, task_name, opts)

        acc = insert_installs(acc, install_names, insert_before)
        adds_deps = schema.adds_deps

        {igniter, acc, schema} =
          installs
          |> Enum.reduce({igniter, acc, schema}, fn install, {igniter, acc, schema} ->
            name =
              if is_tuple(install) do
                elem(install, 0)
              else
                install
              end

            compose_install_and_validate!(
              igniter,
              argv,
              %{
                schema
                | composes: ["#{name}.install"],
                  installs: [],
                  adds_deps: []
              },
              task_name,
              Keyword.delete(opts, :only),
              :schema,
              name,
              acc
            )
          end)

        compose_install_and_validate!(
          igniter,
          argv,
          %{
            schema
            | adds_deps: schema.adds_deps ++ adds_deps
          },
          task_name,
          Keyword.delete(opts, :only),
          return,
          insert_before,
          acc
        )
    end
  end

  defp insert_installs(acc, install_names, insert_before) do
    if insert_before in acc do
      Enum.flat_map(acc, fn item ->
        if item == insert_before do
          install_names ++ [item]
        else
          [item]
        end
      end)
    else
      install_names ++ acc
    end
  end

  defp raise_on_conflicts!(schema, argv) do
    flag_conflicts =
      schema.flag_conflicts
      |> Map.drop(Keyword.keys(Igniter.Mix.Task.Info.global_options()[:switches]))
      |> Enum.filter(fn {_, list} ->
        Enum.count(list) > 1
      end)
      |> Map.new(fn {k, v} ->
        {"--" <> String.replace(to_string(k), "_", "-"), v}
      end)

    alias_conflicts =
      schema.alias_conflicts
      |> Map.drop(Keyword.keys(Igniter.Mix.Task.Info.global_options()[:aliases]))
      |> Enum.flat_map(fn {k, list} ->
        case Enum.uniq_by(list, &elem(&1, 0)) do
          [] -> []
          [_] -> []
          list -> [{k, Enum.uniq(Enum.map(list, &elem(&1, 1)))}]
        end
      end)
      |> Map.new(fn {k, v} ->
        {"-" <> String.replace(to_string(k), "_", "-"), v}
      end)

    if Enum.empty?(flag_conflicts) and Enum.empty?(alias_conflicts) do
      :ok
    else
      Enum.each(argv, fn arg ->
        cond do
          conflicting = flag_conflicts[arg] ->
            Mix.shell().error("""
            Ambiguous flag provided: `#{arg}`

            The tasks or task groups `#{Enum.join(conflicting, ", ")}` all define the flag `#{arg}`.

            To disambiguate, provide the arg as `--<prefix>.#{String.trim_leading(arg, "--")}`,
            where `<prefix>` is the task or task group name.

            For example:

            `--#{Enum.at(conflicting, 0)}.#{String.trim_leading(arg, "--")}`
            """)

            exit({:shutdown, 2})

          conflicting = alias_conflicts[arg] ->
            Mix.shell().error("""
            Ambiguous flag provided: `#{arg}`

            The tasks or task groups `#{Enum.join(conflicting, ", ")}` all define the flag `#{arg}`.

            To disambiguate, provide the arg as `-<prefix>.#{String.trim_leading(arg, "-")}`,
            where `<prefix>` is the task or task group name.

            For example:

            `--#{Enum.at(conflicting, 0)}.#{String.trim_leading(arg, "-")}`
            """)

            exit({:shutdown, 2})

          true ->
            :ok
        end
      end)
    end
  end

  defp maybe_set_dep_options(igniter, install_names, argv, parent, opts) do
    Enum.reduce(install_names, igniter, fn install, igniter ->
      composing_task = "#{install}.install"

      with composing_task when not is_nil(composing_task) <- Mix.Task.get(composing_task),
           true <- function_exported?(composing_task, :info, 2),
           composing_schema when not is_nil(composing_schema) <-
             composing_task.info(argv, parent) do
        options =
          if composing_schema.only && !opts[:only] do
            Keyword.put(composing_schema.dep_opts, :only, composing_schema.only)
          else
            composing_schema.dep_opts
          end

        if options == [] do
          igniter
        else
          Enum.reduce(options, igniter, fn {key, val}, igniter ->
            val =
              if key == :only do
                List.wrap(val)
              else
                val
              end

            Igniter.Project.Deps.set_dep_option(igniter, install, key, val)
          end)
        end
      else
        _ ->
          igniter
      end
    end)
  end

  defp add_deps(igniter, add_deps, opts) do
    Enum.reduce(add_deps, igniter, fn dependency, igniter ->
      with {name, _, dep_opts} <- dependency,
           only when not is_nil(only) <- dep_opts[:only],
           false <- Mix.env() in only do
        igniter
        |> Igniter.assign(
          :failed_to_add_deps,
          [name | igniter.assigns[:failed_to_add_deps] || []]
        )
        |> Igniter.add_warning("""
        Dependency #{inspect(dependency)} could not be installed,
        because it is configured to be installed with `only: #{inspect(only)}`.

        Please install it manually, for example:

            `MIX_ENV=#{Enum.at(only, 0)} mix igniter.install #{dependency}`.
        """)
      else
        _ ->
          new_igniter =
            Igniter.Project.Deps.add_dep(
              igniter,
              dependency,
              Keyword.merge(opts, error?: true, notify_on_present?: true, yes?: !!opts[:yes])
            )

          name =
            case dependency do
              {name, _} -> name
              {name, _, _} -> name
            end

          if Enum.count(igniter.issues) != Enum.count(new_igniter.issues) ||
               Enum.count(igniter.warnings) != Enum.count(new_igniter.warnings) do
            Igniter.assign(
              new_igniter,
              :failed_to_add_deps,
              [name | igniter.assigns[:failed_to_add_deps] || []]
            )
          else
            new_igniter
          end
      end
    end)
  end

  def validate!(argv, schema, task_name)
  def validate!(_argv, nil, _task_name), do: {[], []}

  def validate!(argv, schema, task_name) do
    group = group(schema, task_name)

    argv = args_for_group(argv, group)

    merged_schema = recursively_compose_schema(schema, argv, task_name, [])

    options_key =
      if merged_schema.extra_args? do
        :switches
      else
        :strict
      end

    OptionParser.parse!(
      argv,
      [
        {options_key, clean_csv(merged_schema.schema || [])},
        {:aliases, merged_schema.aliases || []}
      ]
    )
  end

  defp clean_csv(schema) do
    Enum.map(schema, fn
      {k, :csv} ->
        {k, :keep}

      {k, v} ->
        {k, v}
    end)
  end

  @doc false
  def args_for_group(argv, group) do
    case argv do
      ["--" <> arg, "-" <> v2 | rest] ->
        with true <- String.starts_with?(arg, "#{group}."),
             [_, actual_arg] <- String.split(arg, "#{group}.", parts: 2) do
          ["--" <> actual_arg] ++ args_for_group(["-" <> v2 | rest], group)
        else
          _ ->
            rest_args = args_for_group(["-" <> v2 | rest], group)

            if String.contains?(arg, ".") do
              rest_args
            else
              ["--#{arg}"] ++ rest_args
            end
        end

      ["-" <> arg, "-" <> v2 | rest] ->
        with true <- String.starts_with?(arg, "#{group}."),
             [_, actual_arg] <- String.split(arg, "#{group}.", parts: 2) do
          ["-" <> actual_arg] ++ args_for_group(["-" <> v2 | rest], group)
        else
          _ ->
            rest_args = args_for_group(["-" <> v2 | rest], group)

            if String.contains?(arg, ".") do
              rest_args
            else
              ["-#{arg}"] ++ rest_args
            end
        end

      ["--" <> arg | rest] ->
        with true <- String.starts_with?(arg, "#{group}."),
             [_, actual_arg] <- String.split(arg, "#{group}.", parts: 2) do
          ["--" <> actual_arg] ++ args_for_group(rest, group)
        else
          _ ->
            rest_args = args_for_group(rest, group)

            if String.contains?(arg, ".") do
              rest_args
            else
              ["--#{arg}"] ++ rest_args
            end
        end

      ["-" <> arg | rest] ->
        with true <- String.starts_with?(arg, "#{group}."),
             [_, actual_arg] <- String.split(arg, "#{group}.", parts: 2) do
          ["-" <> actual_arg] ++ args_for_group(rest, group)
        else
          _ ->
            rest_args = args_for_group(rest, group)

            if String.contains?(arg, ".") do
              rest_args
            else
              ["-#{arg}"] ++ rest_args
            end
        end

      [v1 | rest] ->
        [v1] ++ args_for_group(rest, group)

      [] ->
        []
    end
  end

  defp recursively_compose_schema(%Info{composes: []} = schema, _argv, _parent, _opts), do: schema

  defp recursively_compose_schema(%Info{composes: [compose | rest]} = schema, argv, parent, opts) do
    with composing_task when not is_nil(composing_task) <- Mix.Task.get(compose),
         true <- function_exported?(composing_task, :info, 2),
         composing_schema when not is_nil(composing_schema) <- composing_task.info(argv, parent) do
      composing_task_name = Mix.Task.task_name(composing_task)

      composing_schema =
        if opts[:only] do
          %{composing_schema | only: opts[:only]}
        else
          composing_schema
        end

      recursively_compose_schema(
        %{
          schema
          | schema:
              merge_schemas(
                schema.schema,
                composing_schema.schema
              ),
            aliases:
              merge_aliases(
                schema.aliases,
                composing_schema.aliases
              ),
            flag_conflicts: flag_conflicts(schema, composing_schema, composing_task_name),
            alias_conflicts: alias_conflicts(schema, composing_schema, composing_task_name),
            composes: rest,
            extra_args?: schema.extra_args? || composing_schema.extra_args?,
            installs: Keyword.merge(composing_schema.installs, schema.installs),
            adds_deps: Keyword.merge(composing_schema.adds_deps, schema.adds_deps)
        },
        argv,
        parent,
        Keyword.delete(opts, :only)
      )
      |> Map.put(:composes, List.wrap(composing_schema.composes))
      |> recursively_compose_schema(argv, composing_task_name, Keyword.delete(opts, :only))
    else
      _ ->
        recursively_compose_schema(
          %{schema | composes: rest},
          argv,
          parent,
          Keyword.delete(opts, :only)
        )
    end
  end

  defp flag_conflicts(schema, composing_schema, composing_task_name) do
    Map.merge(
      schema.flag_conflicts,
      flag_groups(composing_schema, composing_task_name),
      fn _key, schema_value, composing_value ->
        Enum.uniq(schema_value ++ composing_value)
      end
    )
  end

  defp alias_conflicts(schema, composing_schema, composing_task_name) do
    Map.merge(
      schema.alias_conflicts,
      alias_groups(composing_schema, composing_task_name),
      fn _key, schema_value, composing_value ->
        Enum.uniq(schema_value ++ composing_value)
      end
    )
  end

  @doc false
  def group(%{group: group}, _task_name) when not is_nil(group),
    do: String.replace(to_string(group), "_", "-")

  def group(_, task_name), do: String.replace(task_name, "_", "-")

  defp merge_schemas(schema, composing_schema) do
    schema = schema || []
    composing_schema = composing_schema || []

    Keyword.merge(composing_schema, schema)
  end

  defp merge_aliases(aliases, composing_aliases) do
    aliases = aliases || []
    composing_aliases = composing_aliases || []

    Keyword.merge(composing_aliases, aliases)
  end

  defp flag_groups(schema, task_name) do
    Map.new(schema.schema, fn {k, _} ->
      {k, [group(schema, task_name)]}
    end)
  end

  defp alias_groups(schema, task_name) do
    Map.new(schema.aliases, fn {k, v} ->
      {k, [{v, group(schema, task_name)}]}
    end)
  end
end
