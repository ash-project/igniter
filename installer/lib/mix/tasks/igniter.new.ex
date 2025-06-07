defmodule Mix.Tasks.Igniter.New do
  @moduledoc """
  Creates a new project using `mix new`, and adds `igniter` to the project.

  ## Options

  All options are passed through to underlying installers, except for the following:

  * `--install` - A comma-separated list of dependencies to install using
    `mix igniter.install` after creating the project.
  * `--example` - Request example code to be added to the project when installing packages.
  * `--with` - The command to use instead of `new`, i.e `phx.new`
  * `--with-args` - Additional arguments to pass to the installer provided in `--with`
  * `--yes` or `-y` - Skips confirmations during installers. The `-y` option cannot be applied
    to the `--with` command, as it may or may not support it. Use `--with-args`
    to provide arguments to that command.
  * `--no-installer-version-check` - skip the version check for the latest igniter_new version
  * `--git` - Initialize a git repository in the project directory and commit the initial state.

  ## Options for `mix.new`

  * `--module` - The base module name to use for the project.
  * `--sup` - Generates an OTP application skeleton including a supervision tree.
  * `--umbrella` - Generates an umbrella project.

  Example

      mix igniter.new my_project --install foo,bar,baz --with=phx.new --with-args="--no-ecto"
  """
  @shortdoc "Creates a new Igniter application"
  use Mix.Task

  @igniter_version "~> 0.6"
  @installer_version Igniter.New.MixProject.project()[:version]

  @impl Mix.Task
  def run(argv) do
    {argv, positional} = extract_positional_args(argv)

    name =
      case positional do
        [name | _] ->
          name

        _ ->
          Mix.shell().error("""
          Required positional argument missing: project_name.

          Usage:

              mix igniter.new project_name [options]
          """)

          exit({:shutdown, 1})
      end

    if String.starts_with?(name, "-") do
      Mix.shell().error("""
      The first positional argument must be a project name that starts with a dash, got: #{name}
      """)

      exit({:shutdown, 1})
    end

    {options, _, _} =
      OptionParser.parse(argv,
        strict: [
          install: :keep,
          local: :string,
          example: :boolean,
          with: :string,
          module: :string,
          sup: :boolean,
          umbrella: :boolean,
          installer_version_check: :boolean,
          git: :boolean
        ],
        aliases: [i: :install, l: :local, e: :example, w: :with]
      )

    install_with = options[:with] || "new"

    if String.match?(install_with, ~r/\s/) do
      Mix.shell().error("The --with option must not contain any spaces, got: #{install_with}")

      exit({:shutdown, 1})
    end

    install =
      options
      |> Keyword.get_values(:install)
      |> List.wrap()
      |> Enum.join(",")
      |> String.split(",", trim: true)

    if File.exists?(name) do
      Mix.shell().error("""
      The directory #{name} already exists. You must either:
      1. remove or move it
      2. If you are trying to modify an existing project add `{:igniter` to the project, if it is not
      already added, and then run `mix igniter.install #{Enum.join(install, ",")}` inside the project
      """)

      exit({:shutdown, 1})
    end

    version_task =
      if Keyword.get(options, :installer_version_check, true) do
        get_latest_version("igniter_new")
      end

    with_args =
      [name | with_args(argv)]

    with_args =
      if install_with == "phx.new" do
        with_args ++ ["--install"]
      else
        with_args
      end

    with_args =
      if options[:module] do
        with_args ++ ["--module", options[:module]]
      else
        with_args
      end

    with_args =
      if options[:sup] do
        with_args ++ ["--sup"]
      else
        with_args
      end

    with_args =
      if options[:umbrella] do
        with_args ++ ["--umbrella"]
      else
        with_args
      end

    yes =
      if "--yes" in argv or "-y" in argv do
        "--yes"
      end

    do_warn_outdated(version_task, yes: yes)

    Mix.Task.run(install_with, with_args)

    version_requirement =
      if options[:local] do
        local = Path.join(["..", options[:local]])
        "path: #{inspect(local)}, override: true"
      else
        inspect(@igniter_version)
      end

    if "--umbrella" in with_args or "--umbrella" in argv do
      Mix.shell().exit("""
      igniter.new is not currently compatible with umbrella applications

      Additionally, many package installers do not support umbrella applications.

      If you are sure that you want to use umbrella applications (there are plenty
      of good reasons), please generate the application using `mix #{install_with}`,
      and then run installers from individual applications.
      """)

      exit({:shutdown, 1})
    end

    File.cd!(name)

    contents =
      "mix.exs"
      |> File.read!()

    if String.contains?(contents, "{:igniter") do
      Mix.shell().info(
        "It looks like the project already exists and igniter is already installed, not adding it to deps."
      )
    else
      # the spaces are required here to avoid the need for a format
      new_contents =
        contents
        |> add_igniter_dep(version_requirement)
        |> Code.format_string!()

      File.write!("mix.exs", new_contents)
    end

    Igniter.Installer.Loading.with_spinner(
      "Fetching and compiling dependencies",
      fn ->
        System.cmd("mix", ["deps.get"])
        System.cmd("mix", ["deps.compile", "--long-compilation-threshold", "0"])
      end
    )

    if !Enum.empty?(install) do
      example =
        if options[:example] do
          "--example"
        end

      install_args =
        Enum.filter([Enum.join(install, ","), example, yes], & &1)

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

      rest_args =
        try do
          rest_args(argv)
        rescue
          _ ->
            []
        end

      Mix.Task.run(
        "igniter.install",
        install_args ++
          rest_args ++ ["--yes-to-deps", "--from-igniter-new", "--new-with", "phx-new"]
      )
    end

    if options[:git] do
      initialize_git_repo()
    end

    :ok
  end

  defp do_warn_outdated(version_task, opts) do
    if version_task do
      try do
        # if we get anything else than a `Version`, we'll get a MatchError
        # and fail silently
        %Version{} = latest_version = Task.await(version_task, 3_000)
        maybe_warn_outdated(latest_version, opts)
      rescue
        _e ->
          :ok
      catch
        :abort ->
          exit({:shutdown, 1})

        :exit, _e ->
          :ok
      end
    end
  end

  defp with_args(argv, acc \\ [])

  defp with_args([], acc) do
    acc
  end

  defp with_args(["--with-args=" <> args | rest], acc) do
    with_args(rest, acc ++ OptionParser.split(args))
  end

  defp with_args(["--with-args", next | rest], acc) do
    with_args(rest, acc ++ OptionParser.split(next))
  end

  defp with_args([_next | rest], acc) do
    with_args(rest, acc)
  end

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

  @flags ~w(example sup umbrella installer-version-check no-installer-version-check git)
  @flags_with_values ~w(install local with with-args module)
  @switches ~w(e)
  @switches_with_values ~w(i l)

  # I don't feel like I should have to do this
  # seems like something missing in OptionParser
  defp rest_args(args) do
    args
    |> Enum.flat_map(&String.split(&1, ~r/(?<!\\)=/, parts: 2, trim: true))
    |> do_rest_args()
  end

  defp do_rest_args([]), do: []

  defp do_rest_args(["--" <> flag | rest])
       when flag in @flags do
    do_rest_args(rest)
  end

  defp do_rest_args(["--" <> flag, _value | rest]) when flag in @flags_with_values do
    do_rest_args(rest)
  end

  defp do_rest_args(["-" <> flag, "-" <> next | rest])
       when flag in @switches or flag in @switches_with_values do
    do_rest_args(["-" <> next | rest])
  end

  defp do_rest_args(["-" <> flag, _value | rest]) when flag in @switches_with_values do
    do_rest_args(rest)
  end

  defp do_rest_args(["-" <> flag, "-" <> next | rest]) do
    ["-#{flag}" | do_rest_args(["-" <> next | rest])]
  end

  defp do_rest_args(["-" <> flag, next | rest]) do
    ["-#{flag}", next | do_rest_args(rest)]
  end

  defp do_rest_args(["--" <> flag]) when flag in @flags or flag in @flags_with_values do
    []
  end

  defp do_rest_args(["-" <> flag]) when flag in @switches or flag in @switches_with_values do
    []
  end

  defp do_rest_args([other]), do: [other]

  @doc false
  def add_igniter_dep(contents, version_requirement) do
    if String.contains?(contents, "defp deps do\n    []") do
      String.replace(
        contents,
        "defp deps do\n    []",
        "defp deps do\n    [{:igniter, #{version_requirement}, only: [:dev, :test]}]"
      )
    else
      String.replace(
        contents,
        "defp deps do\n    [\n",
        "defp deps do\n    [\n      {:igniter, #{version_requirement}, only: [:dev, :test]},\n"
      )
    end
  end

  @doc false
  def igniter_version, do: @igniter_version

  defp initialize_git_repo do
    Igniter.Installer.Loading.with_spinner(
      "Initializing local git repository, staging all files, and committing",
      fn ->
        case System.cmd("git", ["init"]) do
          {_, 0} ->
            case System.cmd("git", ["add", "."]) do
              {_, 0} ->
                case System.cmd("git", ["commit", "-m", "Initial commit"]) do
                  {_, 0} ->
                    Mix.shell().info("Git repository initialized and initial commit created.")

                  {output, _} ->
                    Mix.shell().error("Failed to create initial commit: #{output}")
                end

              {output, _} ->
                Mix.shell().error("Failed to add files to git: #{output}")
            end

          {output, _} ->
            Mix.shell().error("Failed to initialize git repository: #{output}")
        end
      end
    )
  end

  defp maybe_warn_outdated(latest_version, opts) do
    if Version.compare(@installer_version, latest_version) == :lt do
      if opts[:yes] do
        Mix.shell().info([
          :yellow,
          "A new version of igniter.new is available:",
          :green,
          " v#{latest_version}",
          :reset,
          ".",
          "\n",
          "You are currently running ",
          :red,
          "v#{@installer_version}",
          :reset,
          ".\n",
          "To update, run:\n\n",
          "    $ mix local.igniter\n"
        ])
      else
        continue? =
          Mix.shell().yes?(
            IO.iodata_to_binary(
              IO.ANSI.format([
                :yellow,
                "A new version of igniter.new is available:",
                :green,
                " v#{latest_version}",
                :reset,
                ".",
                "\n",
                "You are currently running ",
                :red,
                "v#{@installer_version}",
                :reset,
                ".\n",
                "To update, run:\n\n",
                "    $ mix local.igniter\n\n",
                "Would you like to continue with ",
                :red,
                "v#{@installer_version} ",
                :reset,
                "anyway?"
              ])
            )
          )

        if !continue? do
          throw(:abort)
        end
      end
    end
  end

  # we need to parse JSON, so we only check for new versions on Elixir 1.18+
  if Version.match?(System.version(), "~> 1.18") do
    defp get_latest_version(package) do
      Task.async(fn ->
        # ignore any errors to not prevent the generators from running
        # due to any issues while checking the version
        try do
          with {:ok, package} <- get_package(package) do
            versions =
              for release <- package["releases"],
                  version = Version.parse!(release["version"]),
                  # ignore pre-releases like release candidates, etc.
                  version.pre == [] do
                version
              end

            Enum.max(versions, Version)
          end
        rescue
          e -> {:error, e}
        catch
          :exit, e -> {:error, :exit, e}
        end
      end)
    end

    defp get_package(name) do
      http_options =
        [
          ssl: [
            verify: :verify_peer,
            cacerts: :public_key.cacerts_get(),
            depth: 2,
            customize_hostname_check: [
              match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
            ],
            versions: [:"tlsv1.2", :"tlsv1.3"]
          ]
        ]

      options = [body_format: :binary]

      Application.ensure_all_started(:ssl)
      :inets.start()

      case :httpc.request(
             :get,
             {~c"https://hex.pm/api/packages/#{name}",
              [{~c"user-agent", ~c"Mix.Tasks.Igniter.New/#{@installer_version}"}]},
             http_options,
             options
           ) do
        {:ok, {{_, 200, _}, _headers, body}} ->
          {:ok, JSON.decode!(body)}

        {:ok, {{_, status, _}, _, _}} ->
          {:error, status}

        {:error, reason} ->
          {:error, reason}
      end
    end
  else
    defp get_latest_version(_), do: nil
  end
end
