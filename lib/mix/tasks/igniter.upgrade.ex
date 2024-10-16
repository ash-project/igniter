defmodule Mix.Tasks.Igniter.Upgrade do
  use Igniter.Mix.Task

  @example "mix igniter.upgrade package1 package2@1.2.1"

  @shortdoc "Fetches new versions of dependencies and runs any associated upgrade tasks."
  @moduledoc """
  #{@shortdoc}

  Runs through all upgrade tasks for each upgraded package,  including child dependencies.

  If a major version upgrade is being performed, then we must do this in multiple phases,
  first upgrading to the latest minor version of the current major version, then upgrading
  to the next major version.

  ## Example

  ```bash
  #{@example}
  ```

  ## Options

  * `--yes` or `-y` - Accept all changes automatically
  """

  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :igniter,
      example: @example,
      positional: [
        packages: [rest: true]
      ],
      schema: [
        yes: :boolean
      ],
      aliases: [y: :yes],
      defaults: [yes: false]
    }
  end

  def igniter(igniter, argv) do
    {%{packages: packages}, argv} = positional_args!(argv)
    options = options!(argv)

    Mix.Task.run("compile", ["--no-compile"])
    Mix.Task.reenable("compile")

    original_deps_info =
      Mix.Dep.cached()
      |> expand_deps()
      |> Enum.filter(&match?({:ok, v} when is_binary(v), &1.status))

    igniter =
      igniter
      |> Igniter.include_existing_file("mix.exs")
      |> Igniter.include_existing_file("mix.lock")

    original_mix_exs = Rewrite.Source.get(Rewrite.source!(igniter.rewrite, "mix.exs"), :content)
    original_mix_lock = Rewrite.Source.get(Rewrite.source!(igniter.rewrite, "mix.lock"), :content)

    package_names = Enum.map(packages, &(String.split(&1, "@") |> List.first()))

    igniter =
      packages
      |> Enum.reduce(igniter, &replace_dep(&2, &1))
      |> Igniter.apply_and_fetch_dependencies(
        error_on_abort?: true,
        yes?: options[:yes],
        update_deps: package_names,
        force?: true
      )

    try do
      new_deps_info =
        Mix.Dep.load_and_cache()
        |> expand_deps()
        |> Enum.map(fn dep ->
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
        |> Enum.filter(&match?({:ok, v} when is_binary(v), &1.status))

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
    requirement =
      case Igniter.Project.Deps.determine_dep_type_and_version(package) do
        {package, requirement} ->
          {package, requirement}

        :error ->
          Mix.shell().error("Invalid package identifier: #{package}")
          exit({:shutdown, 1})
      end

    Igniter.Project.Deps.add_dep(igniter, requirement, yes?: true)
  end

  defp expand_deps(deps) do
    if Enum.any?(deps, &(&1.deps != [])) do
      expand_deps(Enum.flat_map(deps, &[%{&1 | deps: []} | &1.deps]))
    else
      Enum.uniq_by(deps, & &1.app)
    end
  end

  # # Loads mix.exs in the current directory or loads the project from the
  # # mixfile cache and pushes the project onto the project stack.
  # defp load_project(app, post_config) do
  #   Mix.ProjectStack.post_config(post_config)

  #   if cached = Mix.State.read_cache({:app, app}) do
  #     {project, file} = cached
  #     push(project, file, app)
  #     project
  #   else
  #     file = Path.expand("mix.exs")
  #     old_proj = get()

  #     {new_proj, file} =
  #       if File.regular?(file) do
  #         old_undefined = Code.get_compiler_option(:no_warn_undefined)

  #         try do
  #           Code.compiler_options(relative_paths: false, no_warn_undefined: :all)
  #           _ = Code.compile_file(file)
  #           get()
  #         else
  #           ^old_proj -> Mix.raise("Could not find a Mix project at #{file}")
  #           new_proj -> {new_proj, file}
  #         after
  #           Code.compiler_options(relative_paths: true, no_warn_undefined: old_undefined)
  #         end
  #       else
  #         push(nil, file, app)
  #         {nil, "nofile"}
  #       end

  #     Mix.State.write_cache({:app, app}, {new_proj, file})
  #     new_proj
  #   end
  # end
end
