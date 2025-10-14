# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs.contributors>
#
# SPDX-License-Identifier: MIT

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

  def igniter(igniter) do
    arguments = igniter.args.positional
    options = igniter.args.options

    upgrades =
      %{
        "0.3.66" => [&code_module_parse_to_project_module_parse/2],
        "0.3.71" => [&code_module_parse_to_project_module_parse/2],
        "0.3.76" => [&code_common_nth_right_to_move_right/2],
        "0.4.0" => [&igniter2_to_igniter1/2]
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
      "Igniter.Code.Module.parse/1 was deprecated in favor of Igniter.Project.Module.parse/1"
    )
  end

  defp code_common_nth_right_to_move_right(igniter, _opts) do
    igniter
    |> Igniter.Refactors.Rename.rename_function(
      {Igniter.Code.Common, :nth_right},
      {Igniter.Code.Common, :move_right},
      arity: 2
    )
    |> Igniter.add_notice(
      "Igniter.Code.Common.nth_right/2 was deprecated in favor of Igniter.Code.Common.move_right/2"
    )
  end

  defp igniter2_to_igniter1(igniter, _opts) do
    ignore_module_conflict(fn ->
      Igniter.Mix.Task.module_info()[:compile][:source] |> List.to_string() |> Code.compile_file()
    end)

    Igniter.update_all_elixir_files(igniter, fn zipper ->
      Igniter.Upgrades.Igniter.rewrite_deprecated_igniter_callback(zipper)
    end)
  end

  defp ignore_module_conflict(fun) when is_function(fun, 0) do
    original_compiler_opts = Code.compiler_options()
    Code.put_compiler_option(:ignore_module_conflict, true)
    result = fun.()
    Code.compiler_options(original_compiler_opts)
    result
  end
end
