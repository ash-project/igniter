if !Code.ensure_loaded?(Mix.Tasks.Igniter.Install) do
  defmodule Mix.Tasks.Igniter.Install do
    @moduledoc """
    Install a package or packages, and run any associated installers.

    ## Args

    mix igniter.install package1 package2 package3

    ## Package formats

    * `package` - The latest version of the package will be installed, pinned at the
       major version, or minor version if there is no major version yet.
    * `package@version` - The package will be installed at the specified version.
       If the version given is generic, like `3.0`, it will be pinned as described above.
       if it is specific, like `3.0.1`, it will be pinned at that *exact* version with `==`.
    * `package@git:git_url` - The package will be installed from the specified git url.
    * `package@github:project/repo` - The package will be installed from the specified github repo.
    * `package@path:path/to/dep` - The package will be installed from the specified path.

    Additionally, a Git ref can be specified when using `git` or `github`:

    * `package@git:git_url@ref`

    ## Switches

    * `--dry-run` - Run the task without making any changes.
    * `--yes` - Automatically answer yes to any prompts.
    * `--yes-to-deps` - Automatically answer yes to any prompts about installing new deps.
    * `--verbose` - display additional output from various operations
    * `--example` - Request that installed packages include initial example code.
    """
    use Mix.Task

    @tasks ~w(deps.loadpaths loadpaths compile deps.compile)

    @impl true
    @shortdoc "Install a package or packages, and run any associated installers."
    def run(argv) do
      message =
        cond do
          "--igniter-repeat" in argv ->
            "setting up igniter"

          "--from-igniter-new" in argv ->
            "installing igniter"

          true ->
            "checking for igniter in project"
        end

      Igniter.Installer.Task.with_spinner(
        message,
        fn ->
          Mix.Task.run("deps.compile")

          if Code.ensure_loaded?(Igniter.Util.Install) do
            Mix.Task.run("deps.compile", ["--no-compile"])
          end
        end,
        verbose?: "--verbose" in argv
      )

      argv = Enum.reject(argv, &(&1 in ["--igniter-repeat", "--from-igniter-new"]))

      if Code.ensure_loaded?(Igniter.Util.Install) do
        {argv, positional} = extract_positional_args(argv)

        packages =
          positional
          |> Enum.join(",")
          |> String.split(",", trim: true)

        if Enum.empty?(packages) do
          raise ArgumentError, "must provide at least one package to install"
        end

        Application.ensure_all_started(:rewrite)

        apply(Igniter.Util.Install, :install, [
          Enum.join(packages, ","),
          argv
        ])
      else
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
              |> Mix.Tasks.Igniter.New.dont_consolidate_protocols_in_dev()
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

            System.cmd("mix", ["deps.get"])

            Igniter.Installer.Task.with_spinner(
              "compiling igniter",
              fn ->
                for task <- @tasks, do: Mix.Task.reenable(task)

                for task <- @tasks do
                  Mix.Task.run(task, [])
                end
              end,
              verbose?: "--verbose" in argv
            )

            Mix.Task.reenable("igniter.install")
            Mix.Task.run("igniter.install", argv ++ ["--igniter-repeat"])
          end
        else
          Mix.shell().error("""
          Not in a mix project. No `mix.exs` file was found.

          Did you mean `mix igniter.new`?
          """)

          exit({:shutdown, 1})
        end
      end
    end

    defp add_igniter_dep(contents) do
      version_requirement = "\"~> 0.5\""

      if String.contains?(contents, "{:igniter") do
        contents
      else
        Mix.Tasks.Igniter.New.add_igniter_dep(contents, version_requirement)
      end
    end

    @doc false
    def extract_positional_args(argv) do
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
end
