defmodule Igniter.Util.Info do
  @moduledoc false

  require Logger
  alias Igniter.Mix.Task.Info

  def compose_install_and_validate!(
        igniter \\ Igniter.new(),
        argv,
        schema,
        task_name,
        opts,
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
        igniter =
          igniter
          |> add_deps(
            List.wrap(schema.adds_deps),
            opts
          )
          |> Igniter.apply_and_fetch_dependencies(opts)

        raise_on_conflicts!(schema, argv)

        {igniter, Enum.uniq(acc), validate!(argv, schema, task_name)}

      installs ->
        schema = %{schema | installs: []}
        install_names = Keyword.keys(installs)

        igniter
        |> add_deps(
          List.wrap(installs),
          opts
        )
        |> Igniter.apply_and_fetch_dependencies(opts)
        |> maybe_set_only(install_names, argv, task_name)
        |> compose_install_and_validate!(
          argv,
          %{
            schema
            | composes: Enum.map(install_names, &"#{&1}.install"),
              installs: [],
              adds_deps: schema.adds_deps
          },
          task_name,
          Keyword.delete(opts, :only),
          acc ++ install_names
        )
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

  defp maybe_set_only(igniter, install_names, argv, parent) do
    Enum.reduce(install_names, igniter, fn install, igniter ->
      composing_task = "#{install}.install"

      with composing_task when not is_nil(composing_task) <- Mix.Task.get(composing_task),
           true <- function_exported?(composing_task, :info, 2),
           composing_schema when not is_nil(composing_schema) <-
             composing_task.info(argv, parent),
           only when not is_nil(only) <- composing_schema.only do
        Igniter.Project.Deps.set_dep_option(igniter, install, :only, only)
      else
        _ ->
          igniter
      end
    end)
  end

  defp add_deps(igniter, add_deps, opts) do
    Enum.reduce(add_deps, igniter, fn dependency, igniter ->
      with {_, _, dep_opts} <- dependency,
           only when not is_nil(only) <- dep_opts[:only],
           false <- Mix.env() in only do
        Igniter.add_warning(igniter, """
        Dependency #{inspect(dependency)} could not be installed,
        because it is configured to be installed with `only: #{inspect(only)}`.

        Please install it manually, for example:

            `MIX_ENV=#{Enum.at(only, 0)} mix igniter.install #{dependency}`.
        """)
      else
        _ ->
          Igniter.Project.Deps.add_dep(
            igniter,
            dependency,
            Keyword.merge(opts, notify_on_present?: true, yes?: !!opts[:yes])
          )
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
        %Info{
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
  def group(%{group: group}, _task_name) when not is_nil(group), do: to_string(group)
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
