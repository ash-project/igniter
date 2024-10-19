defmodule Mix.Tasks.Igniter.UpgradeIgniter do
  use Igniter.Mix.Task

  @example "mix igniter.upgrade_igniter --example arg"

  @moduledoc false

  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      # Groups allow for overlapping arguments for tasks by the same author
      # See the generators guide for more.
      group: :igniter,
      # dependencies to add
      adds_deps: [],
      # dependencies to add and call their associated installers, if they exist
      installs: [],
      # An example invocation
      example: @example,

      # a list of positional arguments, i.e `[:file]`
      positional: [:from, :to],
      # Other tasks your task composes using `Igniter.compose_task`, passing in the CLI argv
      # This ensures your option schema includes options from nested tasks
      composes: [],
      # `OptionParser` schema
      schema: [],
      # Default values for the options in the `schema`.
      defaults: [],
      # CLI aliases
      aliases: [],
      # A list of options in the schema that are required
      required: []
    }
  end

  def igniter(igniter, argv) do
    # extract positional arguments according to `positional` above
    {arguments, argv} = positional_args!(argv)
    # extract options according to `schema` and `aliases` above
    options = options!(argv)

    upgrades =
      %{
        "0.3.66" => [&code_module_parse_to_project_module_parse/2]
      }

    # For each version that requires a change, add it to this map
    # Each key is a version that points at a function that takes an
    # igniter, an argv, and options (i.e flags or other custom options).
    # See the upgrades guide for more.
    Igniter.Upgrades.run(igniter, arguments.from, arguments.to, upgrades, options)
  end

  defp code_module_parse_to_project_module_parse(igniter, _opts) do
    igniter
    |> Igniter.Refactors.Rename.rename_function(
      {Igniter.Code.Module, :parse},
      {Igniter.Project.Module, :parse},
      arity: 1
    )
    |> Igniter.add_notice(
      "Igniter.Code.Module.parse/1 was deprecated in favor of `Igniter.Project.Module.parse/1"
    )
  end
end
