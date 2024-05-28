defmodule Igniter.Module do
  def module_name(suffix) do
    Module.concat(module_name_prefix(), suffix)
  end

  def module_name_prefix() do
    Mix.Project.get!()
    |> Module.split()
    |> :lists.droplast()
    |> Module.concat()
  end
end
