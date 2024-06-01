defmodule Igniter.Deps do
  require Igniter.Common
  alias Sourceror.Zipper
  alias Igniter.Common

  def get_dependency_declaration(igniter, name) do
    zipper =
      igniter
      |> Igniter.include_existing_elixir_file("mix.exs")
      |> Map.get(:rewrite)
      |> Rewrite.source!("mix.exs")
      |> Rewrite.Source.get(:quoted)
      |> Zipper.zip()

    with {:ok, zipper} <- Common.move_to_module_using(zipper, Mix.Project),
         {:ok, zipper} <- Common.move_to_defp(zipper, :deps, 0),
         true <- Common.node_matches_pattern?(zipper, value when is_list(value)),
         {:ok, current_declaration} <-
           Common.move_to_list_item(zipper, fn item ->
             if Common.is_tuple?(item) do
               first_elem = Common.tuple_elem(item, 0)
               first_elem && Common.node_matches_pattern?(first_elem, ^name)
             end
           end) do
      current_declaration
      |> Zipper.subtree()
      |> Zipper.node()
      |> Sourceror.to_string()
    else
      _ ->
        nil
    end
  end

  def add_dependency(igniter, name, version) do
    case get_dependency_declaration(igniter, name) do
      nil ->
        do_add_dependency(igniter, name, version)

      current ->
        desired = "`{#{inspect(name)}, #{inspect(version)}}`"
        current = "`#{current}`"

        if desired == current do
          igniter
        else
          if Mix.shell().yes?("""
             Dependency #{name} is already in mix.exs. Should we replace it?

             Desired: #{desired}
             Found: #{current}
             """) do
            igniter
            |> remove_dependency(name)
            |> do_add_dependency(name, version)
          else
            igniter
          end
        end
    end
  end

  defp remove_dependency(igniter, name) do
    igniter
    |> Igniter.update_file("mix.exs", fn source ->
      quoted = Rewrite.Source.get(source, :quoted)

      new_quoted =
        with zipper <- Zipper.zip(quoted),
             {:ok, zipper} <- Common.move_to_module_using(zipper, Mix.Project),
             {:ok, zipper} <- Common.move_to_defp(zipper, :deps, 0),
             true <- Common.node_matches_pattern?(zipper, value when is_list(value)),
             current_declaration_index when not is_nil(current_declaration_index) <-
               Common.find_list_item_index(zipper, fn item ->
                 if Common.is_tuple?(item) do
                   first_elem = Common.tuple_elem(item, 0)
                   first_elem && Common.node_matches_pattern?(first_elem, ^name)
                 end
               end) do
          zipper
          |> Common.remove_index(current_declaration_index)
          |> Zipper.root()
        else
          _ ->
            quoted
        end

      if new_quoted == quoted do
        Rewrite.Source.add_issue(
          source,
          "Failed to remove dependency #{inspect(name)}"
        )
      else
        Rewrite.Source.update(source, :add_dependency, :quoted, new_quoted)
      end
    end)
  end

  defp do_add_dependency(igniter, name, version) do
    igniter
    |> Igniter.update_file("mix.exs", fn source ->
      quoted = Rewrite.Source.get(source, :quoted)

      new_quoted =
        with zipper <- Zipper.zip(quoted),
             {:ok, zipper} <- Common.move_to_module_using(zipper, Mix.Project),
             {:ok, zipper} <- Common.move_to_defp(zipper, :deps, 0),
             true <- Common.node_matches_pattern?(zipper, value when is_list(value)) do
          quoted =
            quote do
              {unquote(name), unquote(version)}
            end

          zipper
          |> Common.prepend_to_list(quoted)
          |> Zipper.root()
        else
          _ ->
            quoted
        end

      if new_quoted == quoted do
        Rewrite.Source.add_issue(
          source,
          "Failed to add dependency #{inspect({inspect(name), inspect(version)})}"
        )
      else
        Rewrite.Source.update(source, :add_dependency, :quoted, new_quoted)
      end
    end)
  end
end
