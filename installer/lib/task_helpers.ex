# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule Igniter.Installer.TaskHelpers do
  @moduledoc false
  @apps [:logger, :public_key, :ssl, :inets, :eex]
  @tasks [
    "igniter.install": %{
      mfa: {Igniter.CopiedTasks, :install, []}
    },
    "igniter.add": %{
      mfa: {Igniter.CopiedTasks, :add, []}
    },
    "igniter.remove": %{
      mfa: {Igniter.CopiedTasks, :remove, []}
    },
    "igniter.upgrade": %{
      mfa: {Igniter.CopiedTasks, :upgrade, []}
    },
    "igniter.apply_upgrades": %{
      mfa: {Igniter.CopiedTasks, :apply_upgrades, []}
    }
  ]

  def tasks do
    for {task_name, config} <- @tasks do
      task_name = to_string(task_name)
      {task_name, Map.put(config, :module, mod_for_task(task_name))}
    end
  end

  defp mod_for_task(task_name) do
    task_name
    |> String.split(".")
    |> Enum.map(&Macro.camelize/1)
    |> then(&[Mix.Tasks | &1])
    |> Module.concat()
  end

  def copy_docs do
    for {task_name, _} <- tasks() do
      {short_doc_output, 0} =
        System.cmd("mix", ["help", "--search", task_name], cd: "..")

      short_doc =
        short_doc_output
        |> String.split("\n")
        |> Enum.find(&String.starts_with?(&1, "mix #{task_name} "))
        |> String.split("#", parts: 2)
        |> Enum.at(1)
        |> String.trim()

      {long_doc_output, 0} = System.cmd("mix", ["help", task_name], cd: "..")

      long_doc =
        long_doc_output
        |> String.split("\n")
        |> Enum.slice(3..-3//1)
        |> Enum.join("\n")
        |> String.trim()

      File.mkdir_p!("priv/docs/#{task_name}")
      File.write!("priv/docs/#{task_name}/short.txt", short_doc)
      File.write!("priv/docs/#{task_name}/long.txt", long_doc)
    end
  end

  def long_doc(task_name) do
    path = "priv/docs/#{task_name}/long.txt"

    if File.exists?(path) do
      File.read!(path)
    else
      "unknown"
    end
  end

  def short_doc(task_name) do
    path = "priv/docs/#{task_name}/short.txt"

    if File.exists?(path) do
      File.read!(path)
    else
      "unknown"
    end
  end

  def wrap_task(task_name, {module, fun, args}, argv) do
    prevent_infinite_loops!(argv)
    load_deps(argv)
    ensure_apps_started!()
    update_igniter(argv)

    argv = Enum.reject(argv, &(&1 in ["--igniter-repeat", "--from-igniter-new"]))

    if Code.ensure_loaded?(module) do
      apply(module, fun, [argv] ++ args)
    else
      if File.exists?("mix.exs") do
        ensure_igniter_and_install(task_name, argv)
      else
        Mix.shell().error("""
        Not in a mix project. No `mix.exs` file was found.

        Did you mean `mix igniter.new`?
        """)

        exit({:shutdown, 1})
      end
    end
  end

  defp ensure_igniter_and_install(task_name, argv) do
    cleanup? = ensure_igniter!()

    if !Process.get(:registered_on_exit?) do
      Process.put(:registered_on_exit?, true)

      System.at_exit(fn _ ->
        cleanup(cleanup?, argv)
      end)
    end

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

    Mix.Task.reenable(task_name)
    Mix.Task.run(task_name, argv ++ ["--igniter-repeat"])
  end

  defp cleanup(cleanup?, argv) do
    if cleanup? do
      Igniter.Installer.Loading.with_spinner(
        "cleaning up",
        fn ->
          apply(Igniter.CopiedTasks, :remove, [["igniter", "--yes"]])
        end,
        verbose?: "--verbose" in argv
      )
    end
  end

  defp ensure_igniter! do
    contents =
      "mix.exs"
      |> File.read!()

    new_contents =
      contents
      |> add_igniter_dep()

    if contents == new_contents do
      contents
    else
      Igniter.Installer.Loading.with_spinner(
        "temporarily adding igniter",
        fn ->
          new_contents
          |> Code.format_string!()
        end
      )
    end

    if new_contents == contents && !String.contains?(contents, "{:igniter,") do
      Mix.shell().error("""
      Failed to add igniter to mix.exs. Please add it manually and try again

      For more information, see: https://hexdocs.pm/igniter/readme.html#installation
      """)

      exit({:shutdown, 1})
    end

    File.write!("mix.exs", new_contents)
    new_contents != contents
  end

  defp load_deps(argv) do
    message =
      cond do
        "--igniter-repeat" in argv ->
          "setting up igniter"

        "--from-igniter-new" in argv ->
          "installing igniter"

        true ->
          "checking for igniter in project"
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
  end

  defp update_igniter(argv) do
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
  end

  defp ensure_apps_started! do
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

    Application.ensure_all_started(:rewrite)
  end

  defp prevent_infinite_loops!(argv) do
    if Enum.count(argv, &(&1 == "--igniter-repeat")) > 1 do
      Mix.shell().error("""
      There was a problem installing or setting up igniter.

      Run your command again with `--verbose` to see more detail.
      """)

      exit({:shutdown, 1})
    end
  end

  defp add_igniter_dep(contents) do
    version_requirement = "\"~> 0.6\""

    if String.contains?(contents, "{:igniter") do
      contents
    else
      Mix.Tasks.Igniter.New.add_igniter_dep(contents, version_requirement)
    end
  end
end
