defmodule Igniter.Module do
  @moduledoc "Codemods and tools for generating and working with Elixir modules"
  def module_name(suffix) do
    Module.concat(module_name_prefix(), suffix)
  end

  def module_name_prefix do
    Mix.Project.get!()
    |> Module.split()
    |> :lists.droplast()
    |> Module.concat()
  end
end
