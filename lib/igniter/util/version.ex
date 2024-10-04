defmodule Igniter.Util.Version do
  @moduledoc "Utilities for working versions and version requirements"

  @doc """
  Provides a general requirement for a given version string.

  For example

  `3.1.2` would be `~> 3.0`
  and
  `0.2.4` would be `~> 0.2`
  """
  @spec version_string_to_general_requirement!(String.t()) :: String.t() | no_return
  def version_string_to_general_requirement!(version) do
    case version_string_to_general_requirement(version) do
      {:ok, requirement} -> requirement
      {:error, error} -> raise ArgumentError, error
    end
  end

  def version_string_to_general_requirement(version) do
    version
    |> pad_zeroes()
    |> Version.parse()
    |> case do
      {:ok, %Version{major: major, minor: minor, patch: patch, pre: pre}} when pre != [] ->
        {:ok, "~> #{major}.#{minor}.#{patch}-#{Enum.join(pre, ".")}"}

      {:ok, %Version{major: 0, minor: minor}} ->
        {:ok, "~> 0.#{minor}"}

      {:ok, %Version{major: major}} ->
        {:ok, "~> #{major}.0"}

      :error ->
        {:error, "invalid version string"}
    end
  end

  defp pad_zeroes(version) do
    case String.split(version, ".", trim: true) do
      [_major, _minor] -> version <> ".0"
      [_major] -> version <> ".0.0"
      _ -> version
    end
  end
end
