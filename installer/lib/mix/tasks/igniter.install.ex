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

    @apps [:logger, :public_key, :ssl, :inets, :eex]

    @impl true
    @shortdoc "Install a package or packages, and run any associated installers."
    def run(argv) do
      if Enum.count(argv, &(&1 == "--igniter-repeat")) > 1 do
        Mix.shell().error("""
        There was a problem installing or setting up igniter.

        Run your command again with `--verbose` to see more detail.
        """)

        exit({:shutdown, 1})
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
            Igniter.Installer.Loading.with_spinner(
              "temporarily adding igniter",
              fn ->
                new_contents =
                  contents
                  |> add_igniter_dep()

                if contents == new_contents do
                  contents
                else
                  new_contents
                  |> Code.format_string!()
                end
              end
            )

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

            Mix.Task.reenable("igniter.install")
            Mix.Task.run("igniter.install", argv ++ ["--igniter-repeat"])

            if new_contents != contents do
              Igniter.Installer.Loading.with_spinner(
                "cleaning up",
                fn ->
                  Mix.Task.run("igniter.remove", ["igniter", "--yes"])
                end,
                verbose?: "--verbose" in argv
              )
            end
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
      version_requirement = "\"~> 0.6\""

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
