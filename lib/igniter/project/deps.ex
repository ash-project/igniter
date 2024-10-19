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
    case get_dependency_declaration(igniter, name) do
      nil ->
        do_add_dependency(igniter, name, version, opts)

      current ->
        desired = Code.eval_string("{#{inspect(name)}, #{inspect(version)}}") |> elem(0)
        current = Code.eval_string(current) |> elem(0)

        if desired == current do
          if opts[:notify_on_present?] do
            Mix.shell().info(
              "Dependency #{name} is already in mix.exs with the desired version. Skipping."
            )
          end

          igniter
        else
          if opts[:yes?] ||
               Igniter.Util.IO.yes?("""
               Dependency #{name} is already in mix.exs. Should we replace it?

               Desired: `#{inspect(desired)}`
               Found: `#{inspect(current)}`
               """) do
            do_add_dependency(igniter, name, version, opts)
          else
            igniter
          end
        end
    end
  end

  @doc "Sets a dependency option for an existing dependency"
  @spec set_dep_option(Igniter.t(), atom(), atom(), quoted :: term) :: Igniter.t()
  def set_dep_option(igniter, name, key, quoted) do
    Igniter.update_elixir_file(igniter, "mix.exs", fn zipper ->
      with {:ok, zipper} <- Igniter.Code.Module.move_to_module_using(zipper, Mix.Project),
           {:ok, zipper} <- Igniter.Code.Function.move_to_defp(zipper, :deps, 0),
           true <- Igniter.Code.List.list?(zipper),
           {:ok, zipper} <-
             Igniter.Code.List.move_to_list_item(zipper, fn zipper ->
               if Igniter.Code.Tuple.tuple?(zipper) do
                 case Igniter.Code.Tuple.tuple_elem(zipper, 0) do
                   {:ok, first_elem} ->
                     Common.nodes_equal?(first_elem, name)

                   :error ->
                     false
                 end
               end
             end) do
        case Igniter.Code.Tuple.tuple_elem(zipper, 2) do
          {:ok, zipper} ->
            Igniter.Code.Keyword.set_keyword_key(zipper, key, quoted, fn zipper ->
              {:ok,
               Igniter.Code.Common.replace_code(
                 zipper,
                 quoted
               )}
            end)

          :error ->
            with {:ok, zipper} <- Igniter.Code.Tuple.tuple_elem(zipper, 1),
                 true <- Igniter.Code.List.list?(zipper) do
              Igniter.Code.Keyword.set_keyword_key(
                zipper,
                key,
                quoted,
                fn zipper ->
                  {:ok,
                   Igniter.Code.Common.replace_code(
                     zipper,
                     quoted
                   )}
                end
              )
            else
              _ ->
                Igniter.Code.Tuple.append_elem(zipper, [{key, quoted}])
            end
        end
      else
        _ ->
          {:ok, zipper}
      end
    end)
  end

  @doc "Gets the current dependency declaration in mix.exs for a given dependency."
  def get_dependency_declaration(igniter, name) do
    zipper =
      igniter
      |> Igniter.include_existing_file("mix.exs")
      |> Map.get(:rewrite)
      |> Rewrite.source!("mix.exs")
      |> Rewrite.Source.get(:quoted)
      |> Zipper.zip()

    with {:ok, zipper} <- Igniter.Code.Module.move_to_module_using(zipper, Mix.Project),
         {:ok, zipper} <- Igniter.Code.Function.move_to_defp(zipper, :deps, 0),
         true <- Common.node_matches_pattern?(zipper, value when is_list(value)),
         {:ok, current_declaration} <-
           Igniter.Code.List.move_to_list_item(zipper, fn item ->
             if Igniter.Code.Tuple.tuple?(item) do
               case Igniter.Code.Tuple.tuple_elem(item, 0) do
                 {:ok, first_elem} ->
                   Common.nodes_equal?(first_elem, name)

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

  @doc "Removes a dependency from mix.exs"
  def remove_dep(igniter, name) do
    igniter
    |> Igniter.update_elixir_file("mix.exs", fn zipper ->
      with {:ok, zipper} <- Igniter.Code.Module.move_to_module_using(zipper, Mix.Project),
           {:ok, zipper} <- Igniter.Code.Function.move_to_defp(zipper, :deps, 0),
           true <- Igniter.Code.List.list?(zipper),
           current_declaration_index when not is_nil(current_declaration_index) <-
             Igniter.Code.List.find_list_item_index(zipper, fn item ->
               if Igniter.Code.Tuple.tuple?(item) do
                 case Igniter.Code.Tuple.tuple_elem(item, 0) do
                   {:ok, first_elem} ->
                     Common.nodes_equal?(first_elem, name)

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
           {:ok, zipper} <- Igniter.Code.Function.move_to_defp(zipper, :deps, 0),
           true <- Igniter.Code.List.list?(zipper) do
        match =
          Igniter.Code.List.move_to_list_item(zipper, fn zipper ->
            if Igniter.Code.Tuple.tuple?(zipper) do
              case Igniter.Code.Tuple.tuple_elem(zipper, 0) do
                {:ok, first_elem} ->
                  Common.nodes_equal?(first_elem, name)

                :error ->
                  false
              end
            end
          end)

        quoted =
          if opts[:dep_opts] do
            quote do
              {unquote(name), unquote(version), unquote(opts[:dep_opts])}
            end
          else
            {:__block__, [],
             [
               {{:__block__, [], [name]}, {:__block__, [], [version]}}
             ]}
          end

        case match do
          {:ok, zipper} ->
            Igniter.Code.Common.replace_code(zipper, quoted)

          _ ->
            if Keyword.get(opts, :append?, false) do
              Igniter.Code.List.append_to_list(zipper, quoted)
            else
              Igniter.Code.List.prepend_to_list(zipper, quoted)
            end
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

  @doc false
  def determine_dep_type_and_version(requirement) do
    case String.split(requirement, "@", trim: true, parts: 2) do
      [package] ->
        if Regex.match?(~r/^[a-z][a-z0-9_]*$/, package) do
          :inets.start()
          :ssl.start()
          url = ~c"https://hex.pm/api/packages/#{package}"

          case :httpc.request(:get, {url, [{~c"User-Agent", ~c"igniter-installer"}]}, [], []) do
            {:ok, {{_version, _, _reason_phrase}, _headers, body}} ->
              case Jason.decode(body) do
                {:ok,
                 %{
                   "releases" => releases
                 } = body} ->
                  case first_non_rc_version_or_first_version(releases, body) do
                    %{"version" => version} ->
                      {String.to_atom(package),
                       Igniter.Util.Version.version_string_to_general_requirement!(version)}

                    _ ->
                      :error
                  end

                _ ->
                  :error
              end

            _ ->
              :error
          end
        else
          :error
        end

      [package, version] ->
        case version do
          "git:" <> requirement ->
            if String.contains?(requirement, "@") do
              case String.split(requirement, ["@"], trim: true) do
                [url, ref] ->
                  [git: url, ref: ref, override: true]

                _ ->
                  :error
              end
            else
              [git: requirement, override: true]
            end

          "github:" <> requirement ->
            if String.contains?(requirement, "@") do
              case String.split(requirement, ["/", "@"], trim: true) do
                [org, project, ref] ->
                  [github: "#{org}/#{project}", ref: ref, override: true]

                _ ->
                  :error
              end
            else
              [github: requirement, override: true]
            end

          "path:" <> requirement ->
            [path: requirement, override: true]

          version ->
            case Version.parse(version) do
              {:ok, version} ->
                "== #{version}"

              _ ->
                case Igniter.Util.Version.version_string_to_general_requirement(version) do
                  {:ok, requirement} ->
                    requirement

                  _ ->
                    :error
                end
            end
        end
        |> case do
          :error ->
            :error

          requirement ->
            {String.to_atom(package), requirement}
        end
    end
  end

  defp first_non_rc_version_or_first_version(releases, body) do
    releases = Enum.reject(releases, &body["retirements"][&1["version"]])

    Enum.find(releases, Enum.at(releases, 0), fn release ->
      !rc?(release["version"])
    end)
  end

  # This just actually checks if there is any pre-release metadata
  defp rc?(version) do
    version
    |> Version.parse!()
    |> Map.get(:pre)
    |> Enum.any?()
  end
end
