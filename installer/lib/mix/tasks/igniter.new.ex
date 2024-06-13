defmodule Mix.Tasks.Igniter.New do
  @moduledoc """
  Creates a new project using `mix new`, and adds `igniter` to the project.

  ## Options

  All options are passed through to `mix new`, except for:

  * `--install` - A comma-separated list of dependencies to install using `mix igniter.install` after creating the project.
  * `--example` - Request example code to be added to the project when installing packages.
  """
  @shortdoc "Creates a new Igniter application"
  use Mix.Task

  @igniter_version Mix.Project.config()[:version]

  @impl Mix.Task
  def run([name | _ ] = argv) do
    {options, argv, _errors} = OptionParser.parse(argv,
      strict: [install: :keep, local: :string, example: :boolean],
      aliases: [i: :install, l: :local, e: :example]
    )

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

    exit = Mix.shell().cmd("mix new #{Enum.join(argv, " ")}")

    if exit == 0 do
      version_requirement =
        if options[:local] do
          local = Path.join(["..", Path.relative_to_cwd(options[:local])])
          "path: #{inspect(local)}"
        else
          inspect(version_requirement())
        end

      File.cd!(name)

      contents =
        "mix.exs"
        |> File.read!()

      if String.contains?(contents, "{:igniter") do
        Mix.shell().info("It looks like the project already exists and igniter is already installed, not adding it to deps.")
      else
        new_contents =
          String.replace(contents, "defp deps do\n    [\n", "defp deps do\n    [\n{:igniter, #{version_requirement}}\n")

        File.write!("mix.exs", new_contents)
      end

      Mix.shell().cmd("mix deps.get")
      Mix.shell().cmd("mix compile")

      unless Enum.empty?(install) do
        example =
          if options[:example] do
            "--example"
          end
        Mix.shell().cmd("mix igniter.install #{Enum.join(install, ",")} --yes #{example}")
      end

    else
      Mix.shell().info("Aborting command because associated `mix new` command failed.")

      exit({:shutdown, 1})
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
