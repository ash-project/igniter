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

  ## Options for `mix.new`

  * `--module` - The base module name to use for the project.
  * `--sup` - Generates an OTP application skeleton including a supervision tree.
  * `--umbrella` - Generates an umbrella project.

  Example

      mix igniter.new my_project --install foo,bar,baz --with=phx.new --with-args="--no-ecto"
  """
  @shortdoc "Creates a new Igniter application"
  use Mix.Task

  @igniter_version "~> 0.5"

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
          with_args: :string,
          module: :string,
          sup: :boolean,
          umbrella: :boolean
        ],
        aliases: [i: :install, l: :local, e: :example, w: :with, wa: :with_args]
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

    with_args =
      [name | OptionParser.split(options[:with_args] || "")]

    with_args =
      if install_with == "phx.new" do
        with_args ++ ["--install", "--from-elixir-install"]
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
      if with_args[:sup] do
        with_args ++ ["--sup"]
      else
        with_args
      end

    with_args =
      if with_args[:umbrella] do
        with_args ++ ["--umbrella"]
      else
        with_args
      end

    Mix.Task.run(install_with, with_args)

    version_requirement =
      if options[:local] do
        local = Path.join(["..", Path.relative_to_cwd(options[:local])])
        "path: #{inspect(local)}, override: true"
      else
        inspect(@igniter_version)
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
        |> dont_consolidate_protocols_in_dev()
        |> Code.format_string!()

      File.write!("mix.exs", new_contents)
    end

    System.cmd("mix", ["deps.get"])
    System.cmd("mix", ["deps.compile", "--long-compilation-threshold", "0"])

    if !Enum.empty?(install) do
      example =
        if options[:example] do
          "--example"
        end

      yes =
        if "--yes" in argv or "-y" in argv do
          "--yes"
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
          _ -> []
        end

      Mix.Task.run(
        "igniter.install",
        install_args ++ rest_args ++ ["--yes-to-deps", "--from-igniter-new"]
      )
    end

    :ok
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

  @flags ~w(example sup umbrella)
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
  def dont_consolidate_protocols_in_dev(contents) do
    if String.contains?(contents, "consolidate_protocols") do
      contents
    else
      String.replace(
        contents,
        "start_permanent: Mix.env() == :prod,\n",
        "start_permanent: Mix.env() == :prod,\n      consolidate_protocols: Mix.env() != :dev,\n"
      )
    end
  end

  @doc false
  def igniter_version, do: @igniter_version
end
