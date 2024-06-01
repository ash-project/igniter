defmodule Igniter.Tasks do
  def app_name do
    Mix.Project.config()[:app]
  end

  def do_or_dry_run(igniter, argv, opts \\ []) do
    igniter = %{igniter | issues: Enum.uniq(igniter.issues)}
    title = opts[:title] || "Igniter"

    sources =
      igniter.rewrite
      |> Rewrite.sources()

    issues =
      Enum.flat_map(sources, fn source ->
        changed_issues =
          if Rewrite.Source.file_changed?(source) do
            ["File has been changed since it was originally read."]
          else
            []
          end

        issues = Enum.uniq(changed_issues ++ Rewrite.Source.issues(source))

        case issues do
          [] -> []
          issues -> [{source, issues}]
        end
      end)

    case issues do
      [_ | _] ->
        explain_issues(issues)
        :issues

      [] ->
        if igniter.issues == [] do
          result_of_dry_run =
            sources
            |> Enum.filter(fn source ->
              Rewrite.Source.updated?(source)
            end)
            |> case do
              [] ->
                unless opts[:quiet_on_no_changes?] do
                  Mix.shell().info("\n#{title}: No proposed changes!\n")
                end

                :dry_run_with_no_changes

              sources ->
                Mix.shell().info("\n#{title}: Proposed changes:\n")

                Enum.each(sources, fn source ->
                  if Rewrite.Source.from?(source, :string) do
                    content_lines =
                      source
                      |> Rewrite.Source.get(:content)
                      |> String.split("\n")
                      |> Enum.with_index()

                    space_padding =
                      content_lines
                      |> Enum.map(&elem(&1, 1))
                      |> Enum.max()
                      |> to_string()
                      |> String.length()

                    diffish_looking_text =
                      Enum.map_join(content_lines, "\n", fn {line, line_number_minus_one} ->
                        line_number = line_number_minus_one + 1

                        "#{String.pad_trailing(to_string(line_number), space_padding)} #{IO.ANSI.yellow()}| #{IO.ANSI.green()}#{line}#{IO.ANSI.reset()}"
                      end)

                    Mix.shell().info("""
                    Create: #{Rewrite.Source.get(source, :path)}

                    #{diffish_looking_text}
                    """)
                  else
                    Mix.shell().info("""
                    Update: #{Rewrite.Source.get(source, :path)}

                    #{Rewrite.Source.diff(source)}
                    """)
                  end
                end)

                :dry_run_with_changes
            end

          if igniter.tasks != [] do
            message =
              if result_of_dry_run in [:dry_run_with_no_changes, :no_changes] do
                "The following tasks will be run"
              else
                "The following tasks will be run after the above changes:"
              end

            Mix.shell().info("""
            #{message}

            #{Enum.map_join(igniter.tasks, "\n", fn {task, args} -> "* #{IO.ANSI.red()}#{task}#{IO.ANSI.yellow()} #{Enum.join(args, " ")}#{IO.ANSI.reset()}" end)}
            """)
          end

          if "--dry-run" in argv || result_of_dry_run == :dry_run_with_no_changes do
            result_of_dry_run
          else
            if "--yes" in argv ||
                 Mix.shell().yes?(opts[:confirmation_message] || "Proceed with changes?") do
              sources
              |> Enum.any?(fn source ->
                Rewrite.Source.updated?(source)
              end)
              |> if do
                igniter.rewrite
                |> Rewrite.write_all()
                |> case do
                  {:ok, _result} ->
                    igniter.tasks
                    |> Enum.each(fn {task, args} ->
                      Mix.Task.run(task, args)
                    end)

                    :changes_made

                  {:error, error} ->
                    igniter
                    |> Igniter.add_issue(error)
                    |> igniter_issues()

                    {:error, error}
                end
              else
                :no_changes
              end
            else
              :changes_aborted
            end
          end
        else
          igniter_issues(igniter)
        end
    end
  end

  defp igniter_issues(igniter) do
    Mix.shell().info("Issues during code generation")

    igniter.issues
    |> Enum.map_join("\n", fn error ->
      if is_binary(error) do
        "* #{error}"
      else
        "* #{Exception.format(:error, error)}"
      end
    end)
    |> Mix.shell().info()
  end

  defp explain_issues(issues) do
    Mix.shell().info("Igniter: Issues found in proposed changes:\n")

    Enum.each(issues, fn {source, issues} ->
      Mix.shell().info("Issues with #{Rewrite.Source.get(source, :path)}")

      issues
      |> Enum.map_join("\n", fn error ->
        if is_binary(error) do
          "* #{error}"
        else
          "* #{Exception.format(:error, error)}"
        end
      end)
      |> Mix.shell().info()
    end)
  end
end
