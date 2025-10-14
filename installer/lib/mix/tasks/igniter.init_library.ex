# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.Igniter.InitLibrary do
  @moduledoc """
  Set up a library to use Igniter. Adds the optional dependency
  and an install task.

  ## Args

  mix igniter.init_library my_lib

  * `--dry-run` - Run the task without making any changes.
  * `--yes` - Automatically answer yes to any prompts.
  * `--yes-to-deps` - Automatically answer yes to any prompts about installing new deps.
  * `--verbose` - display additional output from various operations
  """
  use Mix.Task

  @apps [:logger, :public_key, :ssl, :inets, :eex]

  @impl true
  @shortdoc "Set up a library to use Igniter. Adds the optional dependency and an install task."
  def run(argv) do
    app_name =
      case argv do
        [] ->
          Mix.shell().error("""
          Missing argument: app name

          Try running `mix igniter.init_library my_lib`.
          """)

          exit({:shutdown, 1})

        [app_name] ->
          app_name
      end

    archives_path = Mix.path_for(:archives)

    archive_apps =
      archives_path
      |> File.ls()
      |> case do
        {:ok, entries} ->
          entries

        _ ->
          []
      end
      |> Enum.map(&Mix.Local.archive_ebin/1)
      |> Enum.map(&Path.join([archives_path, &1, "*.app"]))
      |> Enum.flat_map(&Path.wildcard/1)
      |> Enum.map(&Path.basename(&1, ".app"))
      |> Enum.map(&String.to_atom/1)

    for app <- @apps ++ archive_apps do
      try do
        Mix.ensure_application!(app)
      rescue
        _ ->
          :ok
      end
    end

    message =
      cond do
        "--igniter-repeat" in argv ->
          "setting up igniter"

        "--from-igniter-new" in argv ->
          "installing igniter"

        true ->
          "checking for igniter in project"
      end

    if !Process.get(:updated_igniter?) do
      Igniter.Installer.Loading.with_spinner(
        "Updating project's igniter dependency",
        fn ->
          System.cmd("mix", ["deps.update", "igniter"], stderr_to_stdout: true)
        end,
        verbose?: "--verbose" in argv
      )

      Process.put(:updated_igniter?, true)
    end

    Igniter.Installer.Loading.with_spinner(
      message,
      fn ->
        if Code.ensure_loaded?(Igniter.Util.Install) do
          Mix.Task.run("deps.loadpaths", ["--no-deps-check"])
        end
      end,
      verbose?: "--verbose" in argv
    )

    argv = Enum.reject(argv, &(&1 in ["--igniter-repeat", "--from-igniter-new"]))

    if File.exists?("mix.exs") do
      contents =
        "mix.exs"
        |> File.read!()

      new_contents =
        contents
        |> add_igniter_dep()

      new_contents =
        if contents == new_contents do
          contents
        else
          new_contents
          |> Code.format_string!()
        end

      if new_contents == contents && !String.contains?(contents, "{:igniter,") do
        Mix.shell().error("""
        Failed to add igniter to mix.exs. Please add it manually and try again

        For more information, see: https://hexdocs.pm/igniter/readme.html#installation
        """)

        exit({:shutdown, 1})
      else
        File.write!("mix.exs", new_contents)

        Mix.Project.clear_deps_cache()
        Mix.Project.pop()
        Mix.Dep.clear_cached()

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

        Igniter.Installer.Loading.with_spinner(
          "compiling igniter",
          fn ->
            case System.cmd("mix", ["deps.get"]) do
              {_, 0} ->
                :ok

              {output, status} ->
                raise("""
                mix deps.get failed with exit code #{status}.

                Output:

                #{output}
                """)
            end

            Mix.Task.reenable("deps.compile")
            Mix.Task.reenable("deps.loadpaths")
            Mix.Task.run("deps.compile", [])
            Mix.Task.run("deps.loadpaths", ["--no-deps-check"])
            Mix.Task.reenable("deps.compile")
            Mix.Task.reenable("deps.loadpaths")
          end,
          verbose?: "--verbose" in argv
        )

        Mix.Task.run("igniter.gen.task", ["#{app_name}.install"])
      end
    else
      Mix.shell().error("""
      Not in a mix project. No `mix.exs` file was found.

      Did you mean `mix igniter.new`?
      """)

      exit({:shutdown, 1})
    end
  end

  defp add_igniter_dep(contents) do
    version_requirement = "\"~> 0.6\""

    if String.contains?(contents, "{:igniter") do
      Mix.shell().info("Igniter is already in the project.")
      contents
    else
      add_igniter_dep(contents, version_requirement)
    end
  end

  defp add_igniter_dep(contents, version_requirement) do
    if String.contains?(contents, "defp deps do\n    []") do
      String.replace(
        contents,
        "defp deps do\n    []",
        "defp deps do\n    [{:igniter, #{version_requirement}, optional: true, runtime: false]"
      )
    else
      String.replace(
        contents,
        "defp deps do\n    [\n",
        "defp deps do\n    [\n      {:igniter, #{version_requirement}, optional: true, runtime: false},\n"
      )
    end
  end
end
