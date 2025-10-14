# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule Igniter.CopiedTasks do
  @moduledoc false

  def upgrade_switches do
    [
      yes: :boolean,
      yes_to_deps: :boolean,
      all: :boolean,
      only: :string,
      target: :string,
      verbose: :boolean,
      no_archives_check: :boolean,
      git_ci: :boolean
    ]
  end

  def upgrade(original_argv) do
    {argv, positional} = extract_positional_args(original_argv)
    {opts, _} = OptionParser.parse!(argv, switches: upgrade_switches(), aliases: [])

    Igniter.new()
    |> Map.put(:args, %Igniter.Mix.Task.Args{
      positional: %{packages: positional},
      argv: original_argv,
      argv_flags: argv,
      options: opts
    })
    |> Igniter.Upgrades.upgrade()
  end

  def apply_upgrades(original_argv) do
    {argv, positional} = extract_positional_args(original_argv)
    {opts, _} = OptionParser.parse!(argv, switches: [yes: :boolean], aliases: [])

    Igniter.new()
    |> Map.put(:args, %Igniter.Mix.Task.Args{
      positional: %{packages: positional},
      argv: original_argv,
      argv_flags: argv,
      options: opts
    })
    |> do_apply_upgrades()
  end

  def do_apply_upgrades(igniter) do
    packages = igniter.args.positional.packages

    Enum.reduce(packages, igniter, fn package, igniter ->
      case String.split(package, ":", parts: 3, trim: true) do
        [name, from, to] ->
          task_name =
            if name == "igniter" do
              "igniter.upgrade_igniter"
            else
              "#{name}.upgrade"
            end

          Igniter.compose_task(igniter, task_name, [from, to] ++ igniter.args.argv_flags)

        _ ->
          Mix.raise("Invalid package format: #{package}")
      end
    end)
  end

  def add(argv) do
    {argv, positional} = extract_positional_args(argv)

    packages =
      positional
      |> Enum.join(",")
      |> String.split(",", trim: true)

    if Enum.empty?(packages) do
      raise ArgumentError, "must provide at least one package to install"
    end

    opts = opts(argv)

    igniter = Igniter.new()

    packages
    |> Enum.join(",")
    |> String.split(",")
    |> Enum.reduce(igniter, fn dep, igniter ->
      {name, version} = Igniter.Project.Deps.determine_dep_type_and_version!(dep)
      Igniter.Project.Deps.add_dep(igniter, {name, version}, yes?: igniter.args.options[:yes])
    end)
    |> Igniter.add_task("deps.get")
    |> Igniter.do_or_dry_run(opts)
  end

  def remove(argv) do
    {argv, positional} = extract_positional_args(argv)

    packages =
      positional
      |> Enum.join(",")
      |> String.split(",", trim: true)

    if Enum.empty?(packages) do
      raise ArgumentError, "must provide at least one package to remove"
    end

    opts = opts(argv)

    igniter = Igniter.new()

    packages
    |> Enum.join(",")
    |> String.split(",")
    |> Enum.map(&String.to_atom/1)
    |> Enum.reduce(igniter, fn name, igniter ->
      Igniter.Project.Deps.remove_dep(igniter, name)
    end)
    |> Igniter.add_task("deps.clean", ["--unlock", "--unused"])
    |> Igniter.do_or_dry_run(opts)
  end

  @doc false
  def install(argv) do
    {argv, positional} = extract_positional_args(argv)

    packages =
      positional
      |> Enum.join(",")
      |> String.split(",", trim: true)

    if Enum.empty?(packages) do
      raise ArgumentError, "must provide at least one package to install"
    end

    Igniter.Util.Install.install(packages, argv)
  end

  defp opts(argv) do
    yes = "--yes" in argv
    [yes: yes, yes_to_deps: yes]
  end

  @doc false
  defp extract_positional_args(argv) do
    do_extract_positional_args(argv, [], [])
  end

  defp do_extract_positional_args([], argv, positional), do: {argv, positional}

  defp do_extract_positional_args(argv, got_argv, positional) do
    case OptionParser.next(argv, switches: []) do
      {_, _key, true, rest} ->
        do_extract_positional_args(
          rest,
          got_argv ++ [Enum.at(argv, 0)],
          positional
        )

      {_, _key, _value, rest} ->
        count_consumed = Enum.count(argv) - Enum.count(rest)

        do_extract_positional_args(
          rest,
          got_argv ++ Enum.take(argv, count_consumed),
          positional
        )

      {:error, rest} ->
        [first | rest] = rest
        do_extract_positional_args(rest, got_argv, positional ++ [first])
    end
  end
end
