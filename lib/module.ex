defmodule Igniter.Module do
  @moduledoc "Codemods and tools for generating and working with Elixir modules"
  def module_name(suffix) do
    Module.concat(module_name_prefix(), suffix)
  end

  def proper_location(module_name) do
    path =
      module_name
      |> Module.split()
      |> Enum.map(&to_string/1)
      |> Enum.map(&Macro.underscore/1)

    last = List.last(path)
    leading = :lists.droplast(path)

    Path.join(["lib" | leading] ++ ["#{last}.ex"])
  end

  def parse(module_name) do
    module_name
    |> String.split(".")
    |> Module.concat()
  end

  def module_name_prefix do
    Mix.Project.get!()
    |> Module.split()
    |> :lists.droplast()
    |> Module.concat()
  end
end
