defmodule Mix.Tasks.Igniter.Install do
  @moduledoc Installer.Lib.Private.SharedUtils.igniter_install_docs()

  @shortdoc "Creates a new Igniter application"
  use Mix.Task

  @igniter_version "~> 0.3"

  @impl Mix.Task
  def run(argv) do
    contents =
      "mix.exs"
      |> File.read!()

    ran? =
      if !String.contains?(contents, "{:igniter") do
        new_contents =
          contents
          |> add_igniter_dep()

        if contents == new_contents do
          Mix.shell().error("""
          Failed to add the igniter dependency to the project.

          Please manually add it and run this command again:

          {:igniter, #{inspect(@igniter_version)}}
          """)

          exit({:shutdown, 1})
        end

        new_contents =
          new_contents
          |> dont_consolidate_protocols_in_dev()
          |> Code.format_string!()

        File.write!("mix.exs", new_contents)

        true
      end

    if ran? do
      System.cmd("mix", ["deps.get"])
      System.cmd("mix", ["deps.compile"])

      if Mix.Project.get() do
        Mix.Project.clear_deps_cache()
        Mix.Project.pop()
        Mix.Dep.clear_cached()
      end

      Installer.Lib.Private.SharedUtils.reevaluate_mix_exs()
    else
      if !Mix.Project.get() do
        Installer.Lib.Private.SharedUtils.reevaluate_mix_exs()
      end
    end

    IO.inspect("HERE!")

    Mix.Tasks.Igniter.Install.run(argv)
  end

  defp add_igniter_dep(contents) do
    String.replace(
      contents,
      "defp deps do\n    [\n",
      "defp deps do\n    [\n      {:igniter, #{inspect(@igniter_version)}},\n"
    )
  end

  defp dont_consolidate_protocols_in_dev(contents) do
    if String.contains?(contents, "consolidate_protocols:") do
      contents
    else
      String.replace(
        contents,
        "start_permanent: Mix.env() == :prod,\n",
        "start_permanent: Mix.env() == :prod,\n      consolidate_protocols: Mix.env() != :dev,\n"
      )
    end
  end
end
