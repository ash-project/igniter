defmodule Mix.Tasks.Igniter.InstallFromHex do
  use Mix.Task

  @impl true
  def run([install | argv]) do
    install = String.to_atom(install)
    Application.ensure_all_started(:req)

    case Req.get!("https://hex.pm/api/packages/#{install}").body do
      %{
        "releases" => [
          %{"version" => version}
          | _
        ]
      } ->
        requirement =
          version
          |> Version.parse!()
          |> case do
            %Version{major: 0, minor: minor} ->
              "~> 0.#{minor}"

            %Version{major: major} ->
              "~> #{major}.0"
          end

        dependency_add_result =
          Igniter.new()
          |> Igniter.Deps.add_dependency(install, requirement)
          |> Igniter.Tasks.do_or_dry_run(argv,
            title: "Fetching Dependency",
            quiet_on_no_changes?: true
          )

        if dependency_add_result == :issues do
          raise "Exiting due to issues found while fetching dependency"
        end

        if dependency_add_result == :dry_run_with_changes do
          install_dep_now? =
            Mix.shell().yes?("""
            Cannot display any further installation changes without installing the `#{install}` dependency.

            Would you like to install the dependency now?

            This will be the only change made, and then any remaining steps will be displayed as a dry-run.
            """)

          if install_dep_now? do
            Igniter.new()
            |> Igniter.Deps.add_dependency(install, requirement)
            |> Igniter.Tasks.do_or_dry_run(argv -- ["--dry-run"],
              title: "Fetching Dependency",
              quiet_on_no_changes?: true
            )
          end
        end

        case System.cmd("mix", ["deps.get"]) do
          {_, 0} ->
            :ok

          {output, exit} ->
            Mix.shell().info("""
            mix deps.get returned exited with code: `#{exit}`

            #{output}
            """)
        end

        Mix.Task.load_all()
        |> Enum.find(fn module ->
          Mix.Task.task_name(module) == "igniter.install.#{install}"
        end)
        |> case do
          nil ->
            if dependency_add_result in [:dry_run_with_no_changes, :no_changes] do
              Mix.shell().info("Igniter: #{install} already installed")
            else
              if dependency_add_result == :changes_aborted do
                Mix.shell().info("Igniter: #{install} installation aborted")
              else
                Mix.shell().info("Igniter: #{install} installation complete")
              end
            end

          _task ->
            Mix.shell().info("Igniter: Installing #{install}...")
            Mix.Task.run("igniter.install.#{install}", argv)
        end

      _ ->
        raise "No published versions of #{install}"
    end

    :ok
  end
end
