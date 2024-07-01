defmodule Igniter.Util.Options do
  @moduledoc false

  require Logger

  def validate!(argv, schema, task_name)
  def validate!(_argv, nil, _task_name), do: :ok

  def validate!(argv, schema, task_name) do
    merged_schema =
      schema
      |> Map.put_new(:schema, [])
      |> Map.put_new(:composes, [])
      |> Map.put_new(:extra_args?, false)
      |> recursively_compose_schema(argv, task_name)

    options_key =
      if merged_schema[:extra_args?] do
        :switches
      else
        :strict
      end

    OptionParser.parse!(
      argv,
      [
        {options_key, merged_schema[:schema] || []},
        {:aliases, merged_schema[:aliases] || []}
      ]
    )
  end

  defp recursively_compose_schema(%{composes: []} = schema, _argv, _parent), do: schema

  defp recursively_compose_schema(%{composes: [compose | rest]} = schema, argv, parent) do
    with composing_task when not is_nil(composing_task) <- Mix.Task.get(compose),
         true <- function_exported?(composing_task, :info, 2),
         composing_schema when not is_nil(schema) <- composing_task.info(argv, parent) do
      composing_task_name = Mix.Task.task_name(composing_task)

      recursively_compose_schema(
        %{
          schema
          | schema:
              merge_schemas(
                schema[:schema],
                composing_schema[:schema],
                parent,
                composing_task_name
              ),
            aliases:
              merge_aliases(
                schema[:aliases],
                composing_schema[:aliases],
                parent,
                composing_task_name
              ),
            composes: List.wrap(composing_schema[:composes]) ++ rest,
            extra_args?: schema[:extra_args?] || composing_schema[:extra_args?]
        },
        argv,
        composing_task_name
      )
    else
      _ ->
        recursively_compose_schema(
          %{schema | composes: rest, extra_args?: true},
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
