defmodule Igniter.Upgrades do
  @moduledoc """
  Utilities for running upgrades.
  """

  @doc "Run all upgrades from `from` to `to`."
  def run(igniter, from, to, upgrade_map, opts) do
    upgrade_map
    |> Enum.filter(fn {version, _} ->
      Version.match?(version, "> #{from} and <= #{to}")
    end)
    |> Enum.sort_by(&elem(&1, 0), Version)
    |> Enum.flat_map(&List.wrap(elem(&1, 1)))
    |> Enum.reduce(igniter, fn upgrade, igniter ->
      upgrade.(igniter, opts)
    end)
  end
end
