defmodule Igniter.Version do
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
