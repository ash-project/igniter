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

    unless install_with in ["phx.new", "new"] do
      if String.match?(install_with, ~r/\s/) do
        raise ArgumentError, "The --with option must not contain any spaces, got: #{install_with}"
      end
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
        String.replace(
          contents,
          "defp deps do\n    [\n",
          "defp deps do\n    [\n      {:igniter, #{version_requirement}},\n"
        )

      File.write!("mix.exs", new_contents)
    end

    unless Enum.empty?(install) do
      Mix.shell().cmd("mix deps.get")
      Mix.shell().cmd("mix compile")

      example =
        if options[:example] do
          "--example"
        end

      Mix.shell().cmd("mix igniter.install #{Enum.join(install, ",")} --yes #{example}")
    end

    :ok
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
