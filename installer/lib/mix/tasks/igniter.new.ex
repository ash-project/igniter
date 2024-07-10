defmodule Mix.Tasks.Igniter.New do
  @moduledoc """
  Creates a new project using `mix new`, and adds `igniter` to the project.

  ## Options

  All options are passed through to `mix new`, except for:

  * `--install` - A comma-separated list of dependencies to install using `mix igniter.install` after creating the project.
  * `--example` - Request example code to be added to the project when installing packages.
  * `--with` - The command to use instead of `new`, i.e `phx.new`
  """
  @shortdoc "Creates a new Igniter application"
  use Mix.Task

  @igniter_version Mix.Project.config()[:version]

  @impl Mix.Task
  def run([name | _] = argv) do
    {options, argv, _errors} =
      OptionParser.parse(argv,
        strict: [install: :keep, local: :string, example: :boolean, with: :string],
        aliases: [i: :install, l: :local, e: :example, w: :with]
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

    Mix.Task.run(install_with, argv)

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
      case Mix.shell().cmd("mix deps.get") do
        0 ->
          Mix.Project.clear_deps_cache()
          Mix.Project.pop()
          Mix.Dep.clear_cached()

          "mix.exs"
          |> File.read!()
          |> Code.eval_string([], file: Path.expand("mix.exs"))

          Igniter.Util.DepsCompile.run()

        exit_code ->
          Mix.shell().info("""
          mix deps.get returned exited with code: `#{exit_code}`
          """)
      end

      example =
        if options[:example] do
          "--example"
        end

      Mix.Task.run(
        "igniter.install",
        Enum.filter([Enum.join(install, ","), "--yes", example], & &1)
      )
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
