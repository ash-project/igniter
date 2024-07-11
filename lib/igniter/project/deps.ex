defmodule Igniter.Project.Deps do
  @moduledoc "Codemods and utilities for managing dependencies declared in mix.exs"
  require Igniter.Code.Common
  alias Igniter.Code.Common
  alias Sourceror.Zipper

  @doc """
  Adds a dependency to the mix.exs file.

  # Options

  - `:yes?` - Automatically answer yes to any prompts.
  - `:append?` - Append to the dependency list instead of prepending.
  - `:error?` - Returns an error instead of a notice on failure.
  """
  def add_dep(igniter, dep, opts \\ []) do
    case dep do
      {name, version} ->
        add_dependency(igniter, name, version, opts)

      {name, version, version_opts} ->
        if Keyword.keyword?(version) do
          add_dependency(igniter, name, version ++ version_opts, opts)
        else
          add_dependency(igniter, name, version, Keyword.put(opts, :dep_opts, version_opts))
        end

      other ->
        raise ArgumentError, "Invalid dependency: #{inspect(other)}"
    end
  end

  @deprecated "Use `add_dep/2` or `add_dep/3` instead."
  def add_dependency(igniter, name, version, opts \\ []) do
    if name in List.wrap(igniter.assigns[:manually_installed]) do
      igniter
    else
      case get_dependency_declaration(igniter, name) do
        nil ->
          do_add_dependency(igniter, name, version, opts)

        current ->
          desired = "`{#{inspect(name)}, #{inspect(version)}}`"
          current = "`#{current}`"

          if desired == current do
            igniter
          else
            if opts[:yes?] ||
                 Mix.shell().yes?("""
                 Dependency #{name} is already in mix.exs. Should we replace it?

                 Desired: #{desired}
                 Found: #{current}
                 """) do
              igniter
              |> remove_dependency(name)
              |> do_add_dependency(name, version, opts)
            else
              igniter
            end
          end
      end
    end
  end

  def get_dependency_declaration(igniter, name) do
    zipper =
      igniter
      |> Igniter.include_existing_elixir_file("mix.exs")
      |> Map.get(:rewrite)
      |> Rewrite.source!("mix.exs")
      |> Rewrite.Source.get(:quoted)
      |> Zipper.zip()

    with {:ok, zipper} <- Igniter.Code.Module.move_to_module_using(zipper, Mix.Project),
         {:ok, zipper} <- Igniter.Code.Module.move_to_defp(zipper, :deps, 0),
         true <- Common.node_matches_pattern?(zipper, value when is_list(value)),
         {:ok, current_declaration} <-
           Igniter.Code.List.move_to_list_item(zipper, fn item ->
             if Igniter.Code.Tuple.tuple?(item) do
               case Igniter.Code.Tuple.tuple_elem(item, 0) do
                 {:ok, first_elem} ->
                   Common.node_matches_pattern?(first_elem, ^name)

                 :error ->
                   false
               end
             end
           end) do
      current_declaration
      |> Zipper.node()
      |> Sourceror.to_string()
    else
      _ ->
        nil
    end
  end

  defp remove_dependency(igniter, name) do
    igniter
    |> Igniter.update_elixir_file("mix.exs", fn zipper ->
      with {:ok, zipper} <- Igniter.Code.Module.move_to_module_using(zipper, Mix.Project),
           {:ok, zipper} <- Igniter.Code.Module.move_to_defp(zipper, :deps, 0),
           true <- Common.node_matches_pattern?(zipper, value when is_list(value)),
           current_declaration_index when not is_nil(current_declaration_index) <-
             Igniter.Code.List.find_list_item_index(zipper, fn item ->
               if Igniter.Code.Tuple.tuple?(item) do
                 case Igniter.Code.Tuple.tuple_elem(item, 0) do
                   {:ok, first_elem} ->
                     Common.node_matches_pattern?(first_elem, ^name)

                   :error ->
                     false
                 end
               end
             end),
           {:ok, zipper} <- Igniter.Code.List.remove_index(zipper, current_declaration_index) do
        {:ok, zipper}
      else
        _ ->
          {:warning,
           """
           Failed to remove dependency #{inspect(name)} from `mix.exs`.

           Please remove the old dependency manually.
           """}
      end
    end)
  end

  defp do_add_dependency(igniter, name, version, opts) do
    igniter
    |> Igniter.update_elixir_file("mix.exs", fn zipper ->
      with {:ok, zipper} <- Igniter.Code.Module.move_to_module_using(zipper, Mix.Project),
           {:ok, zipper} <- Igniter.Code.Module.move_to_defp(zipper, :deps, 0),
           true <- Common.node_matches_pattern?(zipper, value when is_list(value)) do
        quoted =
          if opts[:dep_opts] do
            quote do
              {unquote(name), unquote(version), unquote(opts[:dep_opts])}
            end
          else
            quote do
              {unquote(name), unquote(version)}
            end
          end

        if Keyword.get(opts, :append?, false) do
          Igniter.Code.List.append_to_list(zipper, quoted)
        else
          Igniter.Code.List.prepend_to_list(zipper, quoted)
        end
      else
        _ ->
          if opts[:error?] do
            {:error,
             """
             Could not add dependency #{inspect({name, version})}

             `mix.exs` file does not contain a simple list of dependencies in a `deps/0` function.
             Please add it manually and run the installer again.
             """}
          else
            {:warning,
             [
               """
               Could not add dependency #{inspect({name, version})}

               `mix.exs` file does not contain a simple list of dependencies in a `deps/0` function.

               Please add it manually.
               """
             ]}
          end
      end
    end)
  end
end
