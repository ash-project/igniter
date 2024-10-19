defmodule Mix.Tasks.Igniter.Upgrade do
  use Igniter.Mix.Task

  @example "mix igniter.upgrade package1 package2@1.2.1"

  @shortdoc "Fetch and upgrade dependencies. A drop in replacement for `mix deps.update` that also runs upgrade tasks."
  @moduledoc """
  #{@shortdoc}

  Updates dependencies via `mix deps.update` and then runs any upgrade tasks for any changed dependencies.

  By default, this task updates to the latest versions allowed by the `mix.exs` file, just like `mix deps.update`.

  To upgrade a package to a specific version, you can specify the version after the package name,
  separated by an `@` symbol. This allows upgrading beyond what your mix.exs file currently specifies,
  i.e if you have `~> 1.0` in your mix.exs file, you can use `mix igniter.upgrade package@2.0` to
  upgrade to version 2.0, which will update your `mix.exs` and run any equivalent upgraders.

  ## Limitations

  The new version of the package must be "compile compatible" with your existing code. See the upgrades guide for more.

  ## Example

  ```bash
  #{@example}
  ```

  ## Options

  * `--yes` or `-y` - Accept all changes automatically
  * `--all` or `-a` - Upgrades all dependencies
  * `--only` or `-o` - only fetches dependencies for given environment
  * `--target` or `-t` - only fetches dependencies for given target
  * `--no-archives-check` or `-n` - does not check archives before fetching deps
  * `--git-ci` or `-g` - Uses git history (HEAD~1) to check the previous versions in the lock file. See the upgrade guides for more.
  """

  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :igniter,
      example: @example,
      positional: [
        packages: [rest: true, optional: true]
      ],
      schema: [
        yes: :boolean,
        all: :boolean,
        only: :string,
        target: :string,
        no_archives_check: :boolean,
        git_ci: :boolean
      ],
      aliases: [y: :yes, a: :all, o: :only, t: :target, n: :no_archives_check, g: :git_ci],
      defaults: [yes: false]
    }
  end

  def igniter(igniter, argv) do
    {%{packages: packages}, argv} = positional_args!(argv)
    options = options!(argv)

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

    Mix.Task.run("compile")

    igniter =
      igniter
      |> Igniter.include_existing_file("mix.exs")
      |> Igniter.include_existing_file("mix.lock")

    original_mix_exs = Rewrite.Source.get(Rewrite.source!(igniter.rewrite, "mix.exs"), :content)
    original_mix_lock = Rewrite.Source.get(Rewrite.source!(igniter.rewrite, "mix.lock"), :content)

    validate_packages!(packages)

    package_names =
      packages
      |> Enum.filter(&String.contains?(&1, "@"))
      |> case do
        [] ->
          nil

        packages ->
          packages
          |> Enum.map(&(String.split(&1, "@") |> List.first()))
          |> Enum.map(&String.to_atom/1)
      end

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

    igniter =
      if options[:git_ci] do
        igniter
      else
        packages
        |> Enum.reduce(igniter, &replace_dep(&2, &1))
        |> Igniter.apply_and_fetch_dependencies(
          error_on_abort?: true,
          yes?: options[:yes],
          update_deps: package_names,
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
                    Installer.Lib.Private.SharedUtils.reevaluate_mix_exs()

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

      Mix.Task.reenable("compile")
      Mix.Task.reenable("loadpaths")
      Mix.Task.run("compile")
      Mix.Task.reenable("compile")

      original_deps_info
      |> dep_changes_in_order(new_deps_info)
      |> Enum.reduce({igniter, []}, fn update, {igniter, missing} ->
        case apply_updates(igniter, update, argv) do
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
          Igniter.add_notice(
            igniter,
            "The packages `#{Enum.join(missing, ", ")}` did not have upgrade tasks."
          )
      end
    rescue
      e ->
        recover_mix_exs_and_lock(
          igniter,
          original_mix_exs,
          original_mix_lock,
          Exception.format(:error, e, __STACKTRACE__)
        )

        reraise e, __STACKTRACE__
    catch
      :exit, reason ->
        recover_mix_exs_and_lock(
          igniter,
          original_mix_exs,
          original_mix_lock,
          "exit: " <> inspect(reason)
        )

        exit(reason)
    end
  end

  defp apply_updates(igniter, {package, from, to}, argv) do
    task =
      if package == :igniter do
        "igniter.upgrade_igniter"
      else
        "#{package}.upgrade"
      end

    with task when not is_nil(task) <- Mix.Task.get(task),
         true <- function_exported?(task, :info, 2) do
      {:ok, task.igniter(igniter, [from, to] ++ argv)}
    else
      _ ->
        {:missing, package}
    end
  end

  defp recover_mix_exs_and_lock(igniter, mix_exs, mix_lock, reason) do
    if !igniter.assigns[:test_mode?] do
      if Igniter.Util.IO.yes?("""
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
      requirement =
        case Igniter.Project.Deps.determine_dep_type_and_version(package) do
          {package, requirement} ->
            {package, requirement}

          :error ->
            Mix.shell().error("Invalid package identifier: #{package}")
            exit({:shutdown, 1})
        end

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
