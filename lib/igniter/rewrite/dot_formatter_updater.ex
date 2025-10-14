# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule Igniter.Rewrite.DotFormatterUpdater do
  @moduledoc false

  alias Rewrite.DotFormatter

  @behaviour Rewrite.Hook

  @formatter ".formatter.exs"

  @impl true
  def handle(:new, project) do
    {:ok, %{project | dot_formatter: dot_formatter(project)}}
  end

  def handle({action, files}, project) when action in [:added, :updated] do
    if dot_formatter?(files) do
      {:ok, %{project | dot_formatter: dot_formatter(project)}}
    else
      :ok
    end
  end

  defp dot_formatter(project) do
    case DotFormatter.read(project,
           ignore_unknown_deps: true,
           ignore_missing_sub_formatters: true
         ) do
      {:ok, dot_formatter} -> dot_formatter
      {:error, _error} -> DotFormatter.default()
    end
  end

  defp dot_formatter?(@formatter), do: true
  defp dot_formatter?(files) when is_list(files), do: Enum.member?(files, @formatter)
  defp dot_formatter?(_files), do: false
end
