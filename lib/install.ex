defmodule Igniter.Install do
  @moduledoc false
  @option_schema [
    strict: [
      example: :boolean,
      dry_run: :boolean,
      yes: :boolean
    ],
    aliases: [
      d: :dry_run,
      e: :example,
      y: :yes
    ]
  ]

  # only supports hex installation at the moment
  def install(install, argv) do
    install_list = String.split(install, ",")

    Application.ensure_all_started(:req)

    {options, _, _unprocessed_argv} =
      OptionParser.parse(argv, @option_schema)

    argv = OptionParser.to_argv(options)

    igniter = Igniter.new()

    {igniter, install_list} =
      install_list
      |> Enum.reduce({igniter, []}, fn install, {igniter, install_list} ->
        case determine_dep_type_and_version(install) do
          {install, requirement} ->
            install = String.to_atom(install)

            if local_dep?(install) do
              Mix.shell().info(
                "Not looking up dependency for #{install}, because a local dependency is detected"
              )

              {igniter, [install | install_list]}
            else
              {Igniter.Deps.add_dependency(igniter, install, requirement, "--yes" in argv),
               [install | install_list]}
            end

          :error ->
            {Igniter.add_issue(
               igniter,
               "Could not determine source for requested package #{install}"
             ), install_list}
        end
      end)

    confirmation_message =
      unless options[:dry_run] do
        "Dependencies changes must go into effect before individual installers can be run. Proceed with changes?"
      end

    dependency_add_result =
      Igniter.do_or_dry_run(igniter, argv,
        title: "Fetching Dependency",
        quiet_on_no_changes?: true,
        confirmation_message: confirmation_message
      )

    if dependency_add_result == :issues do
      raise "Exiting due to issues found while fetching dependency"
    end

    if dependency_add_result == :dry_run_with_changes do
      install_dep_now? =
        Mix.shell().yes?("""
        Cannot run any associated installers for the requested packages without
        commiting changes and fetching dependencies.

        Would you like to do so now? The remaining steps will be displayed as a dry run.
        """)

      if install_dep_now? do
        Igniter.do_or_dry_run(igniter, (argv ++ ["--yes"]) -- ["--dry-run"],
          title: "Fetching Dependency",
          quiet_on_no_changes?: true
        )
      end
    end

    Mix.shell().info("running mix deps.get")

    case Mix.shell().cmd("mix deps.get") do
      0 ->
        Mix.Task.reenable("compile")
        Mix.Task.run("compile")

      exit_code ->
        Mix.shell().info("""
        mix deps.get returned exited with code: `#{exit_code}`
        """)
    end

    all_tasks =
      Enum.filter(Mix.Task.load_all(), &implements_behaviour?(&1, Igniter.Mix.Task))

    igniter =
      Igniter.new()
      |> Igniter.assign(%{manually_installed: install_list})

    install_list
    |> Enum.flat_map(fn install ->
      all_tasks
      |> Enum.find(fn task ->
        Mix.Task.task_name(task) == "#{install}.install"
      end)
      |> List.wrap()
    end)
    |> Enum.reduce(igniter, fn task, igniter ->
      Igniter.compose_task(igniter, task, argv)
    end)
    |> Igniter.do_or_dry_run(argv)

    :ok
  end

  defp implements_behaviour?(module, behaviour) do
    :attributes
    |> module.module_info()
    |> Enum.any?(fn
      {:behaviour, ^behaviour} ->
        true

      # optimizations, probably extremely minor but this is in a tight loop in some places
      {:behaviour, [^behaviour | _]} ->
        true

      {:behaviour, [_, ^behaviour | _]} ->
        true

      {:behaviour, [_, _, ^behaviour | _]} ->
        true

      # never seen a module with three behaviours in real life, let alone four.
      {:behaviour, behaviours} when is_list(behaviours) ->
        module in behaviours

      _ ->
        false
    end)
  rescue
    _ ->
      false
  end

  defp local_dep?(install) do
    config = Mix.Project.config()[:deps][install]
    Keyword.keyword?(config) && config[:path]
  end

  defp determine_dep_type_and_version(requirement) do
    case String.split(requirement, "@", trim: true) do
      [package] ->
        if Regex.match?(~r/^[a-z][a-z0-9_]*$/, package) do
          case Req.get!("https://hex.pm/api/packages/#{package}").body do
            %{
              "releases" => [
                %{"version" => version}
                | _
              ]
            } ->
              {package, Igniter.Version.version_string_to_general_requirement!(version)}

            _ ->
              :error
          end
        else
          :error
        end

      [package, version] ->
        case version do
          "git:" <> requirement ->
            if String.contains?(requirement, "@") do
              case String.split(requirement, ["@"], trim: true) do
                [url, ref] ->
                  [git: url, ref: ref]

                _ ->
                  :error
              end
            else
              [git: requirement]
            end

          "github:" <> requirement ->
            if String.contains?(requirement, "@") do
              case String.split(requirement, ["/", "@"], trim: true) do
                [org, project, ref] ->
                  [github: "#{org}/#{project}", ref: ref]

                _ ->
                  :error
              end
            else
              [github: requirement]
            end

          "local:" <> requirement ->
            [path: requirement]

          "~>" <> version ->
            "~> #{version}"

          "==" <> version ->
            "== #{version}"

          ">=" <> version ->
            ">= #{version}"

          version ->
            case Version.parse(version) do
              {:ok, version} ->
                "== #{version}"

              _ ->
                case Igniter.Version.version_string_to_general_requirement(version) do
                  {:ok, requirement} ->
                    requirement

                  _ ->
                    :error
                end
            end
        end
        |> case do
          :error ->
            :error

          requirement ->
            {package, requirement}
        end
    end
  end
end
