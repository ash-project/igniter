defmodule Igniter.Upgrades do
  @moduledoc """
  Utilities for running upgrades.
  """

  @doc "Run all upgrades from `from` to `to`."
  def run(igniter, from, to, upgrade_map, opts) do
    upgrade_map
    |> Enum.sort_by(&elem(&1, 0), &Version.compare/2)
    |> Enum.drop_while(fn {version, _} ->
      Version.compare(from, version) in [:gt, :eq]
    end)
    |> Enum.take_while(fn {version, _} ->
      Version.compare(to, version) in [:lt, :eq]
    end)
    |> Enum.flat_map(&elem(&1, 1))
    |> Enum.reduce(igniter, fn upgrade, igniter ->
      upgrade.(igniter, opts)
    end)
  end
end
