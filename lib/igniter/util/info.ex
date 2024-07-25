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
    schema = recursively_compose_schema(schema, argv, task_name)

    case schema.installs do
      [] ->
        igniter =
          igniter
          |> add_deps(
            List.wrap(schema.adds_deps) ++ List.wrap(schema.installs),
            opts
          )
          |> Igniter.apply_and_fetch_dependencies(opts)

        {igniter, Enum.map(Enum.uniq(acc), &"#{&1}.install"), validate!(argv, schema, task_name)}

      installs ->
        schema = %{schema |  installs: []}
        install_names = Keyword.keys(installs)

        igniter
        |> Igniter.apply_and_fetch_dependencies(opts)
        |> compose_install_and_validate!(
          argv,
          %{
            schema
            | composes: Enum.map(install_names, &"#{&1}.install"),
              installs: [],
              adds_deps: schema.adds_deps ++ installs
          },
          task_name,
          opts,
          acc ++ install_names
        )
    end
  end

  defp add_deps(igniter, add_deps, opts) do
    Enum.reduce(add_deps, igniter, fn dependency, igniter ->
      Igniter.Project.Deps.add_dep(
        igniter,
        dependency,
        Keyword.put(opts, :notify_on_present?, true)
      )
    end)
  end

  def validate!(argv, schema, task_name)
  def validate!(_argv, nil, _task_name), do: {[], []}

  def validate!(argv, schema, task_name) do
    merged_schema = recursively_compose_schema(schema, argv, task_name)

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

  defp recursively_compose_schema(%Info{composes: []} = schema, _argv, _parent), do: schema

  defp recursively_compose_schema(%Info{composes: [compose | rest]} = schema, argv, parent) do
    with composing_task when not is_nil(composing_task) <- Mix.Task.get(compose),
         true <- function_exported?(composing_task, :info, 2),
         composing_schema when not is_nil(composing_schema) <- composing_task.info(argv, parent) do
      composing_task_name = Mix.Task.task_name(composing_task)

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
        parent
      )
      |> Map.put(:composes, List.wrap(composing_schema.composes))
      |> recursively_compose_schema(argv, composing_task_name)
    else
      _ ->
        recursively_compose_schema(
          %{schema | composes: rest},
          argv,
          parent
        )
    end
  end

  defp merge_schemas(schema, composing_schema, task, composing_task) do
    schema = schema || []
    composing_schema = composing_schema || []

    Keyword.merge(composing_schema, schema, fn key, composing_value, schema_value ->
      Logger.warning("""
      #{composing_task} has a different configuration for argument: #{key}. Using #{task}'s configuration.

      #{composing_task}: #{composing_value}
      #{task}: #{schema_value}
      """)

      schema_value
    end)
  end

  defp merge_aliases(aliases, composing_aliases, task, composing_task) do
    aliases = aliases || []
    composing_aliases = composing_aliases || []

    Keyword.merge(composing_aliases, aliases, fn key, composing_value, schema_value ->
      Logger.warning("""
      #{composing_task} has a different configuration for alias: #{key}. Using #{task}'s configuration.

      #{composing_task}: #{composing_value}
      #{task}: #{schema_value}
      """)

      schema_value
    end)
  end
end
