defmodule Mix.Tasks.Igniter.New do
  @moduledoc """
  Creates a new project using `mix new`, and adds `igniter` to the project.

  ## Options

  All options are passed through to `mix new`, except for:

  * `--install` - A comma-separated list of dependencies to install using `mix igniter.install` after creating the project.
  * `--example` - Request example code to be added to the project when installing packages.
  * `--with` - The command to use instead of `new`, i.e `phx.new`
  * `--with-args` - Additional arguments to pass to the installer provided in `--with`

  ## Options for `mix.new`

  See `mix help new` for more information on the options available for `mix new`.

  * `--module` - The base module name to use for the project.
  * `--sup` - Generates an OTP application skeleton including a supervision tree.
  * `--umbrella` - Generates an umbrella project.

  Example

      mix igniter.new my_project --install foo,bar,baz --with=phx.new --with-args="--no-ecto"
  """
  @shortdoc "Creates a new Igniter application"
  use Mix.Task

  @igniter_version Mix.Project.config()[:version]

  @impl Mix.Task
  def run(argv) do
    {argv, positional} = Installer.Lib.Private.SharedUtils.extract_positional_args(argv)

    name =
      case positional do
        [name | _] ->
          name

        _ ->
          raise ArgumentError, """
          Required positional argument missing: project_name.

          Usage:

              mix igniter.new project_name [options]
          """
      end

    if String.starts_with?(name, "-") do
      raise ArgumentError,
            "The first positional argument must be a project name that starts with a dash, got: #{name}"
    end

    {options, _argv, _errors} =
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
      raise ArgumentError, "The --with option must not contain any spaces, got: #{install_with}"
    end

    install =
      options[:install]
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
      |> IO.inspect()

    Mix.Task.run(install_with, with_args)

    version_requirement =
      if options[:local] do
        local = Path.join(["..", Path.relative_to_cwd(options[:local])])
        "path: #{inspect(local)}, override: true"
      else
        inspect(version_requirement())
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

    unless Enum.empty?(install) do
      example =
        if options[:example] do
          "--example"
        end

      install_args =
        Enum.filter([Enum.join(install, ","), "--yes", example], & &1)

      System.cmd("mix", ["deps.get"])
      System.cmd("mix", ["deps.compile"])
      System.cmd("mix", ["igniter.install" | install_args])
    end

    :ok
  end

  defp add_igniter_dep(contents, version_requirement) do
    String.replace(
      contents,
      "defp deps do\n    [\n",
      "defp deps do\n    [\n      {:igniter, #{version_requirement}},\n"
    )
  end

  defp dont_consolidate_protocols_in_dev(contents) do
    String.replace(
      contents,
      "start_permanent: Mix.env() == :prod,\n",
      "start_permanent: Mix.env() == :prod,\n      consolidate_protocols: Mix.env() != :dev,\n"
    )
  end

  defp version_requirement do
    @igniter_version
    |> Version.parse!()
    |> case do
      %Version{major: 0, minor: minor} ->
        "~> 0.#{minor}"

      %Version{major: major} ->
        "~> #{major}.0"
    end
  end
end
