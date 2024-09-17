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

        {igniter, Enum.map(Enum.uniq(acc), &"#{&1}.install"), validate!(argv, schema, task_name)}

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
            Keyword.put(opts, :notify_on_present?, true)
          )
      end
    end)
  end

  def validate!(argv, schema, task_name)
  def validate!(_argv, nil, _task_name), do: {[], []}

  def validate!(argv, schema, task_name) do
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
        {options_key, merged_schema.schema || []},
        {:aliases, merged_schema.aliases || []}
      ]
    )
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
                composing_schema.schema,
                parent,
                composing_task_name
              ),
            aliases:
              merge_aliases(
                schema.aliases,
                composing_schema.aliases,
                parent,
                composing_task_name
              ),
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

  defp merge_schemas(schema, composing_schema, task, composing_task) do
    schema = schema || []
    composing_schema = composing_schema || []

    Keyword.merge(composing_schema, schema, fn key, composing_value, schema_value ->
      if composing_value != schema_value do
        Logger.warning("""
        #{composing_task} has a different configuration for argument: #{key}. Using #{task}'s configuration.

        #{composing_task}: #{composing_value}
        #{task}: #{schema_value}
        """)
      end

      schema_value
    end)
  end

  defp merge_aliases(aliases, composing_aliases, task, composing_task) do
    aliases = aliases || []
    composing_aliases = composing_aliases || []

    Keyword.merge(composing_aliases, aliases, fn key, composing_value, schema_value ->
      if composing_value != schema_value do
        Logger.warning("""
        #{composing_task} has a different configuration for alias: #{key}. Using #{task}'s configuration.

        #{composing_task}: #{composing_value}
        #{task}: #{schema_value}
        """)
      end

      schema_value
    end)
  end
end
