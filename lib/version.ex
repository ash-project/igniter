defmodule Igniter.Version do
  def version_string_to_general_requirement(version) do
    version
    |> Version.parse!()
    |> case do
      %Version{major: 0, minor: minor} ->
        "~> 0.#{minor}"

      %Version{major: major} ->
        "~> #{major}.0"
    end
  end
end
