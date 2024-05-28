defmodule Igniter.Tasks do
  def app_name do
    Mix.Project.config()[:app]
  end

  def do_or_dry_run(igniter, argv, opts \\ []) do
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

        issues = changed_issues ++ Rewrite.Source.issues(source)

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
                  IO.puts("\n#{title}: No proposed changes!\n")
                end

                :dry_run_with_no_changes

              sources ->
                IO.puts("\n#{title}: Proposed changes:\n")

                Enum.each(sources, fn source ->
                  IO.puts("""
                  #{Rewrite.Source.get(source, :path)}

                  #{Rewrite.Source.diff(source)}
                  """)
                end)

                :dry_run_with_changes
            end

          if "--dry-run" in argv || result_of_dry_run == :dry_run_with_no_changes do
            result_of_dry_run
          else
            if "--yes" in argv || Mix.shell().yes?("Proceed with changes?") do
              sources
              |> Enum.any?(fn source ->
                Rewrite.Source.updated?(source)
              end)
              |> if do
                igniter.rewrite
                |> Rewrite.write_all()

                :changes_made
              else
                :no_changes
              end
            else
              :changes_aborted
            end
          end
        else
          IO.puts("Issues during code generation")

          igniter.issues
          |> Enum.map_join("\n", fn error ->
            if is_binary(error) do
              "* #{error}"
            else
              "* #{Exception.format(:error, error)}"
            end
          end)
          |> IO.puts()
        end
    end
  end

  defp explain_issues(issues) do
    IO.puts("Igniter: Issues found in proposed changes:\n")

    Enum.each(issues, fn {source, issues} ->
      IO.puts("Issues with #{Rewrite.Source.get(source, :path)}")

      issues
      |> Enum.map_join("\n", fn error ->
        if is_binary(error) do
          "* #{error}"
        else
          "* #{Exception.format(:error, error)}"
        end
      end)
      |> IO.puts()
    end)
  end
end
