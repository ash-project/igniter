defmodule Igniter.Extensions.Phoenix do
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
    cond do
      Igniter.Libs.Phoenix.controller?(igniter, module) ->
        [base | rest] = split = Module.split(module)

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

      Igniter.Libs.Phoenix.html?(igniter, module) ->
        [base | rest] = split = Module.split(module)

        [type] = List.last(split) |> String.split("HTML", trim: true)

        rest = :lists.droplast(rest)

        potential_controller_module =
          Module.concat([base | rest] ++ [type <> "Controller"])

        {exists?, _} = Igniter.Code.Module.module_exists?(igniter, potential_controller_module)

        if exists? && Igniter.Libs.Phoenix.controller?(igniter, potential_controller_module) do
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
          :keep
        end

      String.ends_with?(to_string(module), "CoreComponents") &&
          String.contains?(to_string(module), "Web") ->
        :keep

      String.ends_with?(to_string(module), "JSON") && List.last(Module.split(module)) != "JSON" ->
        [base | rest] = split = Module.split(module)

        [type] = List.last(split) |> String.split("JSON", trim: true)

        rest = :lists.droplast(rest)

        potential_controller_module =
          Module.concat([base | rest] ++ [type <> "Controller"])

        {exists?, _} = Igniter.Code.Module.module_exists?(igniter, potential_controller_module)

        if exists? && Igniter.Libs.Phoenix.controller?(igniter, potential_controller_module) do
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
