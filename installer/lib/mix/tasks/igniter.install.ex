if !Code.ensure_loaded?(Mix.Tasks.Igniter.Install) do
  defmodule Mix.Tasks.Igniter.Install do
    @moduledoc Installer.Lib.Private.SharedUtils.igniter_install_docs()
    use Mix.Task

    @tasks ~w(deps.loadpaths loadpaths compile deps.compile)

    @impl true
    @shortdoc "Install a package or packages, and run any associated installers."
    def run(argv) do
      Mix.Task.run("deps.compile", ["--long-compilation-threshold", "300"])

      if Code.ensure_loaded?(Igniter.Util.Install) do
        Code.ensure_compiled(Installer.Lib.Private.SharedUtils)

        if function_exported?(Installer.Lib.Private.SharedUtils, :install, 1) do
          Installer.Lib.Private.SharedUtils.install(argv)
        else
          Mix.shell().error("""
          Failed to install. Please update the project's igniter package and try again.

          `mix igniter.upgrade igniter`

          For more information, see: https://hexdocs.pm/igniter/upgrades.html
          """)

          exit({:shutdown, 1})
        end
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

            Installer.Lib.Private.SharedUtils.reevaluate_mix_exs()

            System.cmd("mix", ["deps.get"])

            for task <- @tasks, do: Mix.Task.reenable(task)

            for task <- @tasks do
              options =
                if String.ends_with?(task, "compile") do
                  ["--long-compilation-threshold", "300"]
                else
                  []
                end

              Mix.Task.run(task, options)
            end

            Mix.Task.reenable("igniter.install")
            Mix.Task.run("igniter.install", argv)
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
      version_requirement = inspect(Installer.Lib.Private.SharedUtils.igniter_version())

      if String.contains?(contents, "{:igniter") do
        contents
      else
        Mix.Tasks.Igniter.New.add_igniter_dep(contents, version_requirement)
      end
    end
  end
end
