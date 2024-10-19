defmodule Igniter.Util.Install do
  @moduledoc """
  Tools for installing packages and running their associated
  installers, if present.

  [!NOTE]
  The functions in this module are not composable, and are primarily meant to
  be used internally and to support building custom tooling on top of Igniter,
  such as [Fireside](https://github.com/ibarakaiev/fireside).
  """

  @doc """
  Installs the provided list of dependencies. `deps` can be either:
  - a string like `"ash,ash_postgres"`
  - a list of strings like `["ash", "ash_postgres", ...]`
  - a list of tuples like `[{:ash, "~> 3.0"}, {:ash_postgres, "~> 2.0"}]`
  """
  def install(deps, argv, igniter \\ Igniter.new(), opts \\ [])

  def install(deps, argv, igniter, opts) when is_binary(deps) do
    deps = String.split(deps, ",")

    install(deps, argv, igniter, opts)
  end

  def install([head | _] = deps, argv, igniter, opts) when is_binary(head) do
    deps =
      Enum.map(deps, fn dep ->
        case Igniter.Project.Deps.determine_dep_type_and_version(dep) do
          {install, requirement} ->
            {install, requirement}

          :error ->
            raise "Could not determine source for requested package #{dep}"
        end
      end)

    install(deps, argv, igniter, opts)
  end

  def install([head | _] = deps, argv, igniter, opts) when is_tuple(head) do
    if Enum.any?(deps, &(elem(&1, 0) == :igniter)) do
      raise ArgumentError,
            "cannot install the igniter package with `mix igniter.install`. Please use `mix igniter.setup` instead."
    end

    global_options =
      Keyword.update!(
        Igniter.Mix.Task.Info.global_options(),
        :switches,
        &Keyword.put(&1, :example, :boolean)
      )

    only =
      argv
      |> OptionParser.parse!(switches: [only: :keep])
      |> elem(0)
      |> Keyword.get_values(:only)
      |> Enum.join(",")
      |> String.split(",", trim: true)
      |> Enum.map(&String.to_atom/1)
      |> case do
        [] -> nil
        value -> value
      end

    if only && Mix.env() not in only do
      raise """
      The `--only` option can only be used when running `mix igniter.install` in an environment
      that matches one of the environments in `--only`. For example:

          MIX_ENV=#{Enum.at(only, 0)} mix igniter.install --only #{Enum.join(only, ",")}
      """
    end

    {igniter, installing, {options, _}} =
      Igniter.Util.Info.compose_install_and_validate!(
        igniter,
        argv,
        %Igniter.Mix.Task.Info{
          schema: global_options[:switches],
          aliases: [],
          installs: deps
        },
        "igniter.install",
        yes: "--yes" in argv,
        only: only,
        append?: Keyword.get(opts, :append?, false)
      )

    igniter = Igniter.apply_and_fetch_dependencies(igniter, options)

    Mix.Task.run("compile")

    {available_tasks, available_task_sources} =
      Enum.zip(installing, Enum.map(installing, &Mix.Task.get("#{&1}.install")))
      |> Enum.filter(fn {_desired_task, source_task} -> source_task end)
      |> Enum.unzip()

    case available_tasks do
      [] ->
        :ok

      [task] ->
        run_installers(
          igniter,
          available_task_sources,
          "The following installer was found and executed: `#{task}`",
          argv,
          options
        )

      tasks ->
        run_installers(
          igniter,
          available_task_sources,
          "The following installers were found and executed: #{Enum.map_join(tasks, ", ", &"`#{&1}`")}",
          argv,
          options
        )
    end

    installing
    |> Enum.filter(&(&1 not in available_tasks))
    |> case do
      [] ->
        :ok

      [package] ->
        IO.puts("The package `#{package}` had no associated installer task.")

      packages ->
        IO.puts("The packages `#{Enum.join(packages, ", ")}` had no associated installer task.")
    end
  end

  defp run_installers(igniter, igniter_task_sources, title, argv, options) do
    igniter_task_sources
    |> Enum.reduce(igniter, fn igniter_task_source, igniter ->
      Igniter.compose_task(igniter, igniter_task_source, argv)
    end)
    |> Igniter.do_or_dry_run(Keyword.put(options, :title, title))

    :ok
  end

  def get_deps!(igniter, opts) do
    Mix.shell().info("running mix deps.get")

    case System.cmd("mix", ["deps.get"], stderr_to_stdout: true) do
      {_output, 0} ->
        igniter =
          case List.wrap(opts[:update_deps]) do
            [] ->
              igniter

            [:all] ->
              System.cmd("mix", ["deps.update", "--all" | opts[:update_deps_args] || []])
              %{igniter | rewrite: Rewrite.drop(igniter.rewrite, ["mix.lock"])}

            to_update ->
              System.cmd("mix", ["deps.update" | to_update] ++ (opts[:update_deps_args] || []))

              %{igniter | rewrite: Rewrite.drop(igniter.rewrite, ["mix.lock"])}
          end

        Mix.Project.clear_deps_cache()
        Mix.Project.pop()
        Mix.Dep.clear_cached()

        Installer.Lib.Private.SharedUtils.reevaluate_mix_exs()

        Igniter.Util.DepsCompile.run(recompile_igniter?: true, force: opts[:force?])

        igniter

      {output, exit_code} ->
        case handle_error(output, exit_code, igniter, opts) do
          {:ok, igniter} ->
            get_deps!(igniter, opts)

          :error ->
            Mix.shell().info("""
            mix deps.get returned exited with code: `#{exit_code}`
            """)

            raise output
        end
    end
  end

  defp handle_error(output, _exit_code, igniter, opts) do
    if String.contains?(output, "Dependencies have diverged") do
      handle_diverged_dependencies(output, igniter, opts)
    else
      :error
    end
  end

  defp handle_diverged_dependencies(rest, igniter, opts) do
    with [_, dep] <-
           String.split(rest, "the :only option for dependency ", parts: 2, trim: true),
         [dep, rest] <- String.split(dep, ["\n", " "], parts: 2, trim: true),
         [_, source1] <- String.split(rest, "> In ", parts: 2, trim: true),
         [source1, rest] <- String.split(source1, ":", parts: 2, trim: true),
         [declaration1, rest] <-
           String.split(rest, "does not match the :only option calculated for",
             parts: 2,
             trim: true
           ),
         [_, source2] <- String.split(rest, "> In ", parts: 2, trim: true),
         [source2, rest] <- String.split(source2, ":", parts: 2, trim: true),
         [declaration2, _] <-
           String.split(rest, "\n\n", parts: 2, trim: true) do
      dep = String.to_atom(dep)
      source1 = parse_source(source1)
      source2 = parse_source(source2)
      # This is hacky :(
      {declaration1, _} = Code.eval_string(String.replace(declaration1, ", ...", ""))
      {declaration2, _} = Code.eval_string(String.replace(declaration2, ", ...", ""))

      with {^dep, req, opts1} <- declaration1,
           {^dep, _, opts2} <- declaration2 do
        opts1 = Keyword.put_new(opts1, :only, [:dev, :test, :prod])
        opts2 = Keyword.put_new(opts2, :only, [:dev, :test, :prod])
        only = List.wrap(opts1[:only]) ++ List.wrap(opts2[:only])

        igniter =
          case Igniter.Project.Deps.get_dependency_declaration(igniter, dep) do
            nil ->
              Igniter.Project.Deps.add_dep(igniter, {dep, req, Keyword.put(opts1, :only, only)},
                yes?: true
              )

            string ->
              {existing_statement, _} = Code.eval_string(string)

              case existing_statement do
                {dep, requirement} when is_binary(requirement) ->
                  if only == [:dev, :test, :prod] do
                    Igniter.Project.Deps.add_dep(igniter, {dep, requirement}, yes?: true)
                  else
                    Igniter.Project.Deps.add_dep(igniter, {dep, requirement, [only: only]},
                      yes?: true
                    )
                  end

                {dep, opts} when is_list(opts) ->
                  if only == [:dev, :test, :prod] do
                    Igniter.Project.Deps.add_dep(igniter, {dep, Keyword.delete(opts, :only)},
                      yes?: true
                    )
                  else
                    Igniter.Project.Deps.add_dep(igniter, {dep, Keyword.put(opts, :only, only)},
                      yes?: true
                    )
                  end

                {dep, requirement, opts} ->
                  if only == [:dev, :test, :prod] do
                    Igniter.Project.Deps.add_dep(
                      igniter,
                      {dep, requirement, Keyword.put(opts, :only, only)},
                      yes?: true
                    )
                  else
                    case Keyword.delete(opts, :only) do
                      [] ->
                        Igniter.Project.Deps.add_dep(
                          igniter,
                          {dep, requirement},
                          yes?: true
                        )

                      new_opts ->
                        Igniter.Project.Deps.add_dep(
                          igniter,
                          {dep, requirement, new_opts},
                          yes?: true
                        )
                    end
                  end

                _ ->
                  :error
              end
          end

        case igniter do
          :error ->
            :error

          igniter ->
            message = """
            There is a conflict in the `only` option for the dependency #{inspect(dep)}, between #{source1} and #{source2}.

            This change includes an update to the `only` option to include all requisite envs. This is normal, and only
            means that the package is used in one or more environments than it originally was.
            """

            {:ok,
             Igniter.apply_and_fetch_dependencies(
               igniter,
               Keyword.merge(opts, message: message, error_on_abort?: true)
             )}
        end
      else
        _ ->
          :error
      end
    else
      _ ->
        :error
    end
  rescue
    _e ->
      :error
  end

  defp parse_source("mix.exs"), do: "your application"

  defp parse_source("deps/" <> dep) do
    case String.split(dep, "/", parts: 2, trim: true) |> Enum.at(0) do
      nil ->
        "deps/#{dep}"

      dep ->
        "the :#{dep} dependency"
    end
  end

  defp parse_source(dep), do: "\"#{dep}\""
end
