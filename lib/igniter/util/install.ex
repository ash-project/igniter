defmodule Igniter.Util.Install do
  @moduledoc false
  @info [
    switches: [
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

  # sobelow_skip ["DOS.StringToAtom", "RCE.CodeModule"]
  def install(install, argv) do
    install_list =
      if is_binary(install) do
        String.split(install, ",")
      else
        Enum.map(List.wrap(install), &to_string/1)
      end

    Application.ensure_all_started(:req)

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
              {Igniter.Project.Deps.add_dependency(igniter, install, requirement,
                 error?: true,
                 yes?: "--yes" in argv
               ), [install | install_list]}
            end

          :error ->
            {Igniter.add_issue(
               igniter,
               "Could not determine source for requested package #{install}"
             ), install_list}
        end
      end)

    igniter = Igniter.apply_and_fetch_dependencies(igniter, cancel_on_abort?: true)

    desired_tasks = Enum.map(install_list, &"#{&1}.install")

    igniter_tasks =
      Mix.Task.load_all()
      |> Stream.map(fn item ->
        Code.ensure_compiled!(item)
        item
      end)
      |> Stream.filter(&implements_behaviour?(&1, Igniter.Mix.Task))
      |> Enum.filter(&(Mix.Task.task_name(&1) in desired_tasks))

    Igniter.Util.Options.validate!(
      argv,
      %{
        schema: @info[:switches],
        aliases: @info[:aliases],
        composes: desired_tasks
      },
      "igniter.install"
    )

    igniter_tasks
    |> Enum.reduce(igniter, fn task, igniter ->
      Igniter.compose_task(igniter, task, argv)
    end)
    |> Igniter.do_or_dry_run(argv)

    :ok
  end

  def implements_behaviour?(module, behaviour) do
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
    case String.split(requirement, "@", trim: true, parts: 2) do
      [package] ->
        if Regex.match?(~r/^[a-z][a-z0-9_]*$/, package) do
          case Req.get!("https://hex.pm/api/packages/#{package}").body do
            %{
              "releases" => [
                %{"version" => version}
                | _
              ]
            } ->
              {package, Igniter.Util.Version.version_string_to_general_requirement!(version)}

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
              [git: requirement, override: true]
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
              [github: requirement, override: true]
            end

          "path:" <> requirement ->
            [path: requirement, override: true]

          version ->
            case Version.parse(version) do
              {:ok, version} ->
                "== #{version}"

              _ ->
                case Igniter.Util.Version.version_string_to_general_requirement(version) do
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
