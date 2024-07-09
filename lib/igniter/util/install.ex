defmodule Igniter.Util.Install do
  @moduledoc false

  def install(install, argv, igniter \\ Igniter.new()) do
    install_list =
      if is_binary(install) do
        String.split(install, ",")
      else
        Enum.map(List.wrap(install), &to_string/1)
      end

    if Enum.any?(install_list, &(&1 == "igniter")) do
      raise ArgumentError,
            "cannot install the igniter package with `mix igniter.install`. Please use `mix igniter.setup` instead."
    end

    Application.ensure_all_started(:req)

    task_installs =
      install_list
      |> Enum.map(fn install ->
        case determine_dep_type_and_version(install) do
          {install, requirement} ->
            {String.to_atom(install), requirement}

          :error ->
            raise "Could not determine source for requested package #{install}"
        end
      end)

    global_options =
      Keyword.update!(
        Igniter.Mix.Task.Info.global_options(),
        :switches,
        &Keyword.put(&1, :example, :boolean)
      )

    {igniter, desired_tasks, {options, _}} =
      Igniter.Util.Info.compose_install_and_validate!(
        igniter,
        argv,
        %Igniter.Mix.Task.Info{
          schema: global_options[:switches],
          aliases: [],
          installs: task_installs
        },
        "igniter.install"
      )

    igniter = Igniter.apply_and_fetch_dependencies(igniter)

    igniter_tasks =
      Mix.Task.load_all()
      |> Stream.map(fn item ->
        Code.ensure_compiled!(item)
        item
      end)
      |> Stream.filter(&implements_behaviour?(&1, Igniter.Mix.Task))
      |> Enum.filter(&(Mix.Task.task_name(&1) in desired_tasks))
      |> Enum.sort_by(
        &Enum.find_index(desired_tasks, fn e -> e == Mix.Task.task_name(&1) end),
        &<=/2
      )

    title =
      case desired_tasks do
        [task] ->
          "Final result of installer: `#{task}`"

        tasks ->
          "Final result of installers: #{Enum.map_join(tasks, ", ", &"`#{&1}`")}"
      end

    igniter_tasks
    |> Enum.reduce(igniter, fn task, igniter ->
      Igniter.compose_task(igniter, task, argv)
    end)
    |> Igniter.do_or_dry_run(Keyword.put(options, :title, title))

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

  # defp local_dep?(install) do
  #   config = Mix.Project.config()[:deps][install]
  #   Keyword.keyword?(config) && config[:path]
  # end

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
