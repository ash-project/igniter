# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule Igniter.Scribe do
  @moduledoc """
  Contains functions for use with the `--scribe` option in Igniter.

  See [the guide](/documentation/documenting-tasks.md) for more.
  """

  @doc """
  Sets the path and title of the document being generated. Only the first call to this is honored.
  """
  def start_document(igniter, title, contents, opts \\ []) do
    if igniter.assigns[:scribe?] do
      igniter
      |> append_content("# #{title}")
      |> append_content(contents)
      |> Igniter.assign(
        :test_files,
        Map.merge(igniter.assigns[:test_files] || %{}, opts[:files] || %{})
      )
    else
      igniter
    end
  end

  @doc """
  Adds a new section to the documentation.
  """
  def section(igniter, header, explanation, callback) do
    if igniter.assigns[:scribe?] do
      current_header = igniter.assigns[:scribe][:header]
      nesting_level = igniter.assigns[:scribe][:nesting_level] || 1

      header = String.duplicate("#", nesting_level + 1) <> " " <> header

      igniter
      |> assign(:header, header)
      |> assign(:nesting_level, nesting_level + 1)
      |> append_content(header)
      |> append_content(explanation)
      |> callback.()
      |> assign(:header, current_header)
      |> assign(:nesting_level, nesting_level)
    else
      callback.(igniter)
    end
  end

  def patch(original_igniter, callback) do
    if original_igniter.assigns[:scribe?] do
      new_igniter = callback.(original_igniter)

      new_igniter.rewrite
      |> Enum.reduce(new_igniter, fn source, igniter ->
        existing_source =
          Rewrite.source(original_igniter.rewrite, source.path)

        lang = if Path.extname(source.path) in [".ex", ".eex"], do: "elixir", else: nil

        case existing_source do
          {:ok, existing_source} ->
            if Rewrite.Source.version(existing_source) == Rewrite.Source.version(source) do
              igniter
            else
              TextDiff.format(
                existing_source |> Rewrite.Source.get(:content) |> eof_newline(),
                source |> Rewrite.Source.get(:content) |> eof_newline(),
                color: false,
                line_numbers: false,
                format: [
                  separator: ""
                ]
              )
              |> IO.iodata_to_binary()
              |> String.trim_trailing()
              |> String.split("\n")
              |> Enum.map_join("\n", fn
                " " <> str -> str
                other -> other
              end)
              |> case do
                "" ->
                  igniter

                diff ->
                  igniter
                  |> append_content("Update `#{source.path}`:")
                  |> append_content("""
                  ```diff
                  #{diff}
                  ```
                  """)
              end
            end

          _ ->
            igniter
            |> append_content("Create `#{source.path}`:")
            |> append_content("""
            ```#{lang}
            #{Rewrite.Source.get(source, :content)}
            ```
            """)
        end
      end)
    else
      callback.(original_igniter)
    end
  end

  @doc false
  def write(igniter, path) do
    File.write!(path, igniter.assigns[:scribe][:content])

    igniter
  end

  defp append_content(igniter, nil) do
    igniter
  end

  defp append_content(igniter, content) do
    assign(igniter, :content, (igniter.assigns[:scribe][:content] || "") <> "\n" <> content)
  end

  defp assign(igniter, key, value) do
    Igniter.assign(igniter, :scribe, Map.put(igniter.assigns[:scribe] || %{}, key, value))
  end

  defp eof_newline(string), do: String.trim_trailing(string) <> "\n"
end
