defmodule Igniter.Extensions.Phoenix do
  @moduledoc """
  A phoenix extension for Igniter.

  Install with `mix igniter.add_extension phoenix`
  """
  use Igniter.Extension

  def proper_location(igniter, module, opts) do
    case Keyword.get(opts, :location_convention, :phoenix_generators) do
      :phoenix_generators ->
        phoenix_generators_proper_location(igniter, module)

      other ->
        raise "Unknown phoenix location convention #{inspect(other)}"
    end
  end

  defp phoenix_generators_proper_location(igniter, module) do
    split = Module.split(module)

    cond do
      String.ends_with?(to_string(module), "Web.Layouts") && Enum.count(split) == 2 ->
        [base | rest] = split

        [type] = List.last(split) |> String.split("Controller", trim: true)

        rest = :lists.droplast(rest)

        {:ok,
         base
         |> Macro.underscore()
         |> Path.join("components")
         |> then(fn path ->
           rest
           |> Enum.map(&Macro.underscore/1)
           |> case do
             [] -> [path]
             nested -> Path.join([path | nested])
           end
           |> Path.join()
         end)
         |> Path.join(Macro.underscore(type) <> ".ex")}

      String.ends_with?(to_string(module), "Controller") && List.last(split) != "Controller" &&
          String.ends_with?(List.first(split), "Web") ->
        [base | rest] = split

        [type] = List.last(split) |> String.split("Controller", trim: true)

        rest = :lists.droplast(rest)

        {:ok,
         base
         |> Macro.underscore()
         |> Path.join("controllers")
         |> then(fn path ->
           rest
           |> Enum.map(&Macro.underscore/1)
           |> case do
             [] -> [path]
             nested -> Path.join([path | nested])
           end
           |> Path.join()
         end)
         |> Path.join(Macro.underscore(type) <> "_controller.ex")}

      String.ends_with?(to_string(module), "HTML") && List.last(split) != "HTML" &&
          String.ends_with?(List.first(split), "Web") ->
        [base | rest] = split

        [type] = List.last(split) |> String.split("HTML", trim: true)

        rest = :lists.droplast(rest)

        potential_controller_module =
          Module.concat([base | rest] ++ [type <> "Controller"])

        {exists?, _} = Igniter.Project.Module.module_exists(igniter, potential_controller_module)

        if List.last(split) == "ErrorHTML" ||
             (exists? && Igniter.Libs.Phoenix.controller?(igniter, potential_controller_module)) do
          {:ok,
           base
           |> Macro.underscore()
           |> Path.join("controllers")
           |> then(fn path ->
             rest
             |> Enum.map(&Macro.underscore/1)
             |> case do
               [] -> [path]
               nested -> Path.join([path | nested])
             end
             |> Path.join()
           end)
           |> Path.join(Macro.underscore(type) <> "_html.ex")}
        else
          :error
        end

      String.ends_with?(to_string(module), "CoreComponents") &&
          String.contains?(to_string(module), "Web") ->
        [base | rest] = split

        [type] = List.last(split) |> String.split("HTML", trim: true)

        rest = :lists.droplast(rest)

        {:ok,
         base
         |> Macro.underscore()
         |> Path.join("components")
         |> then(fn path ->
           rest
           |> Enum.map(&Macro.underscore/1)
           |> case do
             [] -> [path]
             nested -> Path.join([path | nested])
           end
           |> Path.join()
         end)
         |> Path.join(Macro.underscore(type) <> ".ex")}

      String.ends_with?(to_string(module), "JSON") && List.last(Module.split(module)) != "JSON" &&
          String.ends_with?(List.first(Module.split(module)), "Web") ->
        [base | rest] = split

        [type] = List.last(split) |> String.split("JSON", trim: true)

        rest = :lists.droplast(rest)

        potential_controller_module =
          Module.concat([base | rest] ++ [type <> "Controller"])

        {exists?, _} = Igniter.Project.Module.module_exists(igniter, potential_controller_module)

        if List.last(split) == "ErrorJSON" ||
             (exists? && Igniter.Libs.Phoenix.controller?(igniter, potential_controller_module)) do
          {:ok,
           base
           |> Macro.underscore()
           |> Path.join("controllers")
           |> then(fn path ->
             rest
             |> Enum.map(&Macro.underscore/1)
             |> case do
               [] -> [path]
               nested -> Path.join([path | nested])
             end
             |> Path.join()
           end)
           |> Path.join(Macro.underscore(type) <> "_json.ex")}
        else
          :error
        end

      true ->
        :error
    end
  end
end
