# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule Igniter.Upgrades do
  @moduledoc """
  Utilities for running upgrades.
  """

  @doc "Run all upgrades from `from` to `to`."
  def run(igniter, from, to, upgrade_map, opts) do
    upgrade_map
    |> Enum.filter(fn {version, _} ->
      Version.match?(version, "> #{from} and <= #{to}")
    end)
    |> Enum.sort_by(&elem(&1, 0), Version)
    |> Enum.flat_map(&List.wrap(elem(&1, 1)))
    |> Enum.reduce(igniter, fn upgrade, igniter ->
      upgrade.(igniter, opts)
    end)
  end

  @doc false
  def upgrade(igniter) do
    packages = igniter.args.positional.packages
    options = igniter.args.options

    options =
      if options[:git_ci] do
        Keyword.put(options, :yes, true)
      else
        options
      end

    packages =
      packages
      |> Enum.join(",")
      |> String.split(",")

    if Enum.empty?(packages) && !options[:all] do
      Mix.shell().error("""
      Must specify at least one package to upgrade or use --all to upgrade all packages.
      """)

      exit({:shutdown, 1})
    end

    if options[:only] && !Enum.empty?(packages) do
      Mix.shell().error("""
      Cannot specify both --only and package names.
      """)

      exit({:shutdown, 1})
    end

    if options[:target] && !Enum.empty?(packages) do
      Mix.shell().error("""
      Cannot specify both --target and package names.
      """)

      exit({:shutdown, 1})
    end

    original_deps_info =
      if options[:git_ci] do
        System.cmd("git", ["show", "HEAD~1:mix.lock"])
        |> elem(0)
        |> Code.format_string!()
        |> IO.iodata_to_binary()
        |> Code.eval_string()
        |> elem(0)
        |> Enum.flat_map(fn {key, config} ->
          with {_, _, version, _, _, _, _, _} <- config,
               {:ok, _version} <- Version.parse(version) do
            [%{app: key, status: {:ok, version}}]
          else
            _ ->
              []
          end
        end)
      else
        Mix.Dep.cached()
        |> expand_deps()
        |> Enum.filter(&match?({:ok, v} when is_binary(v), &1.status))
      end

    Igniter.Util.Loading.with_spinner(
      "compile",
      fn ->
        Mix.Task.run("compile", [])
      end,
      verbose?: options[:verbose]
    )

    igniter =
      igniter
      |> Igniter.include_existing_file("mix.exs")
      |> Igniter.include_existing_file("mix.lock")

    original_mix_exs = Rewrite.Source.get(Rewrite.source!(igniter.rewrite, "mix.exs"), :content)
    original_mix_lock = Rewrite.Source.get(Rewrite.source!(igniter.rewrite, "mix.lock"), :content)

    validate_packages!(packages)

    package_names =
      packages
      |> Enum.map(&(String.split(&1, "@") |> List.first()))
      |> Enum.map(&String.to_atom/1)

    update_deps_args = update_deps_args(options)

    igniter =
      if options[:git_ci] do
        igniter
      else
        packages
        |> Enum.reduce(igniter, &replace_dep(&2, &1))
        |> Igniter.apply_and_fetch_dependencies(
          error_on_abort?: true,
          yes: options[:yes],
          yes_to_deps: options[:yes_to_deps],
          update_deps: Enum.map(package_names, &to_string/1),
          update_deps_args: update_deps_args,
          force?: true
        )
      end

    try do
      new_deps_info =
        Mix.Dep.load_and_cache()
        |> expand_deps()
        |> then(fn deps ->
          if options[:git_ci] do
            deps
          else
            Enum.map(deps, fn dep ->
              status =
                Mix.Dep.in_dependency(dep, fn _ ->
                  if File.exists?("mix.exs") do
                    Mix.Project.pop()
                    old_undefined = Code.get_compiler_option(:no_warn_undefined)
                    old_relative_paths = Code.get_compiler_option(:relative_paths)
                    old_ignore_module_conflict = Code.get_compiler_option(:ignore_module_conflict)

                    try do
                      Code.compiler_options(
                        relative_paths: false,
                        no_warn_undefined: :all,
                        ignore_module_conflict: true
                      )

                      _ = Code.compile_file("mix.exs")
                    after
                      Code.compiler_options(
                        relative_paths: old_relative_paths,
                        no_warn_undefined: old_undefined,
                        ignore_module_conflict: old_ignore_module_conflict
                      )
                    end

                    {:ok, Mix.Project.get!().project()[:version]}
                  else
                    dep.status
                  end
                end)

              %{dep | status: status}
            end)
          end
        end)
        |> Enum.filter(&match?({:ok, v} when is_binary(v), &1.status))

      Igniter.Util.Loading.with_spinner(
        "compile",
        fn ->
          Mix.Task.reenable("compile")
          Mix.Task.reenable("loadpaths")

          Mix.Task.run("compile", [])
          Mix.Task.reenable("compile")
        end,
        verbose?: options[:verbose]
      )

      dep_changes =
        dep_changes_in_order(original_deps_info, new_deps_info)

      if !options[:git_ci] &&
           Enum.any?(dep_changes, fn {app, _, _} ->
             app in [:igniter, :glob_ex, :rewrite, :sourceror, :spitfire]
           end) do
        Process.put(:no_recover_mix_exs, true)

        upgrades =
          Enum.map_join(dep_changes, " ", fn {app, from, to} ->
            "#{app}:#{from}:#{to}"
          end)

        Mix.raise("""
        Cannot upgrade igniter or its dependencies with `mix igniter.upgrade` in one command.

        The dependency changes have been saved.

        To complete the upgrade, run the following command:

            mix igniter.apply_upgrades #{upgrades}
        """)
      end

      Enum.reduce(dep_changes, {igniter, []}, fn update, {igniter, missing} ->
        case apply_updates(igniter, update) do
          {:ok, igniter} ->
            {igniter, missing}

          {:missing, missing_package} ->
            {igniter, [missing_package | missing]}
        end
      end)
      |> case do
        {igniter, []} ->
          igniter

        {igniter, missing} ->
          missing =
            missing
            |> Enum.sort()
            |> Enum.join(", ")

          upgrades =
            dep_changes
            |> Enum.sort()
            |> Enum.map_join("\n", fn {app, from, to} ->
              "#{app} #{from} => #{to}"
            end)
            |> String.trim_trailing("\n")

          igniter
          |> Igniter.add_notice("The packages `#{missing}` did not have upgrade tasks.")
          |> Igniter.add_notice("Upgraded packages:\n#{upgrades}")
      end
    rescue
      e ->
        if !options[:git_ci] && !Process.get(:no_recover_mix_exs) do
          recover_mix_exs_and_lock(
            igniter,
            original_mix_exs,
            original_mix_lock,
            Exception.format(:error, e, __STACKTRACE__),
            options
          )
        end

        reraise e, __STACKTRACE__
    catch
      :exit, reason ->
        if !options[:git_ci] && !Process.get(:no_recover_mix_exs) do
          recover_mix_exs_and_lock(
            igniter,
            original_mix_exs,
            original_mix_lock,
            "exit: " <> inspect(reason),
            options
          )
        end

        exit(reason)
    end
  end

  defp update_deps_args(options) do
    update_deps_args =
      if only = options[:only] do
        ["--only", only]
      else
        []
      end

    update_deps_args =
      if target = options[:target] do
        ["--target", target] ++ update_deps_args
      else
        update_deps_args
      end

    update_deps_args =
      if options[:no_archives_check] do
        ["--no-archives-check"] ++ update_deps_args
      else
        update_deps_args
      end

    if options[:all] do
      ["--all"] ++ update_deps_args
    else
      update_deps_args
    end
  end

  defp apply_updates(igniter, {package, from, to}) do
    task =
      if package == :igniter do
        "igniter.upgrade_igniter"
      else
        "#{package}.upgrade"
      end

    with task when not is_nil(task) <- Mix.Task.get(task),
         true <- function_exported?(task, :info, 2) do
      {:ok, Igniter.compose_task(igniter, task, [from, to] ++ igniter.args.argv_flags)}
    else
      _ ->
        {:missing, package}
    end
  end

  defp recover_mix_exs_and_lock(igniter, mix_exs, mix_lock, reason, options) do
    if !igniter.assigns[:test_mode?] do
      if options[:yes] ||
           Igniter.Util.IO.yes?("""
           Something went wrong during the upgrade process.

           #{reason}

           Restore mix.exs and mix.lock to their original contents?

           If you don't do this, you will need to reset them to upgrade again,
           or perform any upgrade steps manually.
           """) do
        File.write!("mix.exs", mix_exs)
        File.write!("mix.lock", mix_lock)
      end
    end
  end

  defp dep_changes_in_order(old_deps_info, new_deps_info) do
    new_deps_info
    |> sort_deps()
    |> Enum.flat_map(fn dep ->
      case Enum.find(old_deps_info, &(&1.app == dep.app)) do
        nil ->
          [{dep.app, nil, Version.parse!(elem(dep.status, 1))}]

        %{status: {:ok, old_version}} ->
          [{dep.app, Version.parse!(old_version), Version.parse!(elem(dep.status, 1))}]

        _other ->
          []
      end
    end)
    |> Enum.reject(fn {_app, old, new} ->
      old == new
    end)
  end

  defp sort_deps([]), do: []

  defp sort_deps(deps) do
    free_dep_name =
      Enum.find_value(deps, fn %{app: app, deps: children} ->
        if !Enum.any?(children, fn child ->
             Enum.any?(deps, &(&1.app == child))
           end) do
          app
        end
      end)

    next_dep_name = free_dep_name || elem(Enum.min_by(deps, &length(&1.deps)), 0)

    {[next_dep], others} = Enum.split_with(deps, &(&1.app == next_dep_name))

    [
      next_dep
      | sort_deps(
          Enum.map(others, fn dep ->
            %{dep | deps: Enum.reject(dep.deps, &(&1.app == next_dep_name))}
          end)
        )
    ]
  end

  defp replace_dep(igniter, package) do
    if String.contains?(package, "@") do
      requirement = Igniter.Project.Deps.determine_dep_type_and_version!(package)

      Igniter.Project.Deps.add_dep(igniter, requirement, yes?: true)
    else
      igniter
    end
  end

  defp expand_deps(deps) do
    if Enum.any?(deps, &(&1.deps != [])) do
      expand_deps(Enum.flat_map(deps, &[%{&1 | deps: []} | &1.deps]))
    else
      Enum.uniq_by(deps, & &1.app)
    end
  end

  defp validate_packages!(packages) do
    Enum.each(packages, fn package ->
      package_name = String.split(package, "@") |> Enum.at(0) |> String.to_atom()

      dependency_declaration =
        Mix.Project.get!().project()[:deps] |> Enum.find(&(elem(&1, 0) == package_name))

      if String.contains?(package, "@") do
        is_non_version_updatable_package =
          case dependency_declaration do
            {_dep, opts} when is_list(opts) ->
              !!(opts[:path] || opts[:git] || opts[:github])

            {_dep, _, opts} ->
              !!(opts[:path] || opts[:git] || opts[:github])

            _ ->
              false
          end

        if is_non_version_updatable_package do
          Mix.shell().error("""
          The update specification `#{package}` is invalid because the package `#{package_name}`
          is pointing at a path, git, or github. These do not currently accept versions while upgrading.
          """)
        end
      end

      allowed_envs =
        case dependency_declaration do
          {_dep, opts} when is_list(opts) ->
            opts[:only]

          {_dep, _, opts} ->
            opts[:only]

          _ ->
            nil
        end
        |> List.wrap()

      allowed_envs =
        if allowed_envs == [] do
          nil
        else
          allowed_envs
        end

      if allowed_envs && !(Mix.env() in allowed_envs) do
        package_name = String.split(package, "@") |> Enum.at(0)

        Mix.shell().error("""
        Cannot update apply upgrade `#{package}` because the package `#{package_name}` is only included
        in the following environments: `#{inspect(allowed_envs)}`, but the current environment is `#{Mix.env()}`.

        Rerun this command with `MIX_ENV=#{Enum.at(allowed_envs, 0)} mix igniter.upgrade ...`
        """)
      end
    end)
  end
end
