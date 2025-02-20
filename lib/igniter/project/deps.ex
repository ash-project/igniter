defmodule Igniter.Project.Deps do
  @moduledoc "Codemods and utilities for managing dependencies declared in mix.exs"
  require Igniter.Code.Common
  alias Igniter.Code.Common
  alias Sourceror.Zipper

  @doc """
  Adds a dependency to the mix.exs file.

  ```elixir
  |> Igniter.Project.Deps.add_dep({:my_dependency, "~> X.Y.Z"})
  ```

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
        new_igniter =
          if Keyword.keyword?(version) do
            add_dependency(igniter, name, version ++ version_opts, opts)
          else
            add_dependency(igniter, name, version, Keyword.put(opts, :dep_opts, version_opts))
          end

        new_igniter =
          if Enum.count(igniter.issues) != Enum.count(new_igniter.issues) ||
               Enum.count(igniter.warnings) != Enum.count(new_igniter.warnings) do
            Igniter.assign(
              new_igniter,
              :failed_to_add_deps,
              [name | igniter.assigns[:failed_to_add_deps] || []]
            )
          else
            new_igniter
          end

        new_igniter

      other ->
        raise ArgumentError, "Invalid dependency: #{inspect(other)}"
    end
  end

  @deprecated "Use `add_dep/2` or `add_dep/3` instead."
  def add_dependency(igniter, name, version, opts \\ []) do
    case get_dep(igniter, name) do
      {:ok, nil} ->
        do_add_dependency(igniter, name, version, opts)

      {:error, error} ->
        if opts[:error?] do
          Igniter.add_issue(igniter, error)
        else
          Igniter.add_warning(igniter, error)
        end

      {:ok, current} ->
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

  @doc "Returns true if the given dependency is in `mix.exs`"
  def has_dep?(igniter, name) do
    !!get_dependency_declaration(igniter, name)
  end

  @doc "Gets the current dependency declaration in mix.exs for a given dependency."
  @deprecated "use `get_dep/2` instead, which can return ok/error tuple"
  def get_dependency_declaration(igniter, name) do
    case get_dep(igniter, name) do
      {:ok, dep} -> dep
      _ -> nil
    end
  end

  @doc "Gets the current dependency declaration in mix.exs for a given dependency."
  @spec get_dep(Igniter.t(), name :: atom()) :: {:ok, nil | String.t()} | {:error, String.t()}
  def get_dep(igniter, name) do
    zipper =
      igniter
      |> Igniter.include_existing_file("mix.exs")
      |> Map.get(:rewrite)
      |> Rewrite.source!("mix.exs")
      |> Rewrite.Source.get(:quoted)
      |> Zipper.zip()

    with {:ok, zipper} <- Igniter.Code.Module.move_to_module_using(zipper, Mix.Project),
         {:ok, zipper} <- Igniter.Code.Function.move_to_defp(zipper, :deps, 0) do
      case igniter.assigns[:igniter_exs][:deps_location] || :last_list_literal do
        {m, f, a} ->
          case apply(m, f, [a] ++ [igniter, zipper]) do
            {:ok, zipper} ->
              get_dep_declaration(zipper, name)

            :error ->
              {:error,
               """
               Could not get dependency #{inspect(name)}

               #{inspect(m)}.#{f}/#{Enum.count(a) + 2} did not find a deps location

               Please remove the dependency manually.
               """}
          end

        {:variable, name} ->
          with {:ok, zipper} <-
                 Igniter.Code.Common.move_to(
                   zipper,
                   &Igniter.Code.Common.variable_assignment?(&1, name)
                 ),
               {:ok, zipper} <- Igniter.Code.Function.move_to_nth_argument(zipper, 1),
               true <- Igniter.Code.List.list?(zipper) do
            get_dep_declaration(zipper, name)
          else
            _ ->
              {:error,
               """
               Could not get dependency #{inspect(name)}

               `deps/0` does not contain an assignment of the `#{name}` variable to a literal list

               Please remove the dependency manually.
               """}
          end

        :last_list_literal ->
          zipper = Zipper.rightmost(zipper)

          if Igniter.Code.List.list?(zipper) do
            get_dep_declaration(zipper, name)
          else
            {:error,
             """
             Could not get dependency #{inspect(name)}

             `deps/0` does not end in a list literal that can be read.
             """}
          end
      end
    else
      _ ->
        nil
    end
  end

  defp get_dep_declaration(zipper, name) do
    case Igniter.Code.List.move_to_list_item(zipper, fn item ->
           if Igniter.Code.Tuple.tuple?(item) do
             case Igniter.Code.Tuple.tuple_elem(item, 0) do
               {:ok, first_elem} ->
                 Common.nodes_equal?(first_elem, name)

               :error ->
                 false
             end
           end
         end) do
      {:ok, current_declaration} ->
        {:ok,
         current_declaration
         |> Zipper.node()
         |> Sourceror.to_string()}

      _ ->
        {:ok, nil}
    end
  end

  @doc "Removes a dependency from mix.exs"
  def remove_dep(igniter, name) do
    igniter
    |> Igniter.update_elixir_file("mix.exs", fn zipper ->
      with {:ok, zipper} <- Igniter.Code.Module.move_to_module_using(zipper, Mix.Project),
           {:ok, zipper} <- Igniter.Code.Function.move_to_defp(zipper, :deps, 0) do
        case igniter.assigns[:igniter_exs][:deps_location] || :last_list_literal do
          {m, f, a} ->
            case apply(m, f, [a] ++ [igniter, zipper]) do
              {:ok, zipper} ->
                remove_from_deps_list(zipper, name)

              :error ->
                {:warning,
                 """
                 Could not remove dependency #{inspect(name)}

                 #{inspect(m)}.#{f}/#{Enum.count(a) + 2} did not find a deps location

                 Please remove the dependency manually.
                 """}
            end

          {:variable, name} ->
            with {:ok, zipper} <-
                   Igniter.Code.Common.move_to(
                     zipper,
                     &Igniter.Code.Common.variable_assignment?(&1, name)
                   ),
                 {:ok, zipper} <- Igniter.Code.Function.move_to_nth_argument(zipper, 1),
                 true <- Igniter.Code.List.list?(zipper) do
              remove_from_deps_list(zipper, name)
            else
              _ ->
                {:warning,
                 """
                 Could not remove dependency #{inspect(name)}

                 `deps/0` does not contain an assignment of the `#{name}` variable to a literal list

                 Please remove the dependency manually.
                 """}
            end

          :last_list_literal ->
            zipper = Zipper.rightmost(zipper)

            if Igniter.Code.List.list?(zipper) do
              remove_from_deps_list(zipper, name)
            else
              {:warning,
               """
               Could not remove dependency #{inspect(name)}

               `deps/0` does not end in a list literal that can be removed from.

               Please remove the dependency manually.
               """}
            end
        end
      else
        _ ->
          {:warning,
           """
           Failed to remove dependency #{inspect(name)} from `mix.exs`.

           Please remove the dependency manually.
           """}
      end
    end)
  end

  defp remove_from_deps_list(zipper, name) do
    with current_declaration_index when not is_nil(current_declaration_index) <-
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
  end

  defp do_add_dependency(igniter, name, version, opts) do
    error_tag =
      if opts[:error?] do
        :error
      else
        :warning
      end

    quoted =
      if opts[:dep_opts] && opts[:dep_opts] != [] do
        dep_opts =
          Enum.map(opts[:dep_opts], fn
            {key, {:code, val}} ->
              {key, Sourceror.parse_string!(val)}

            {key, value} ->
              {key, value}
          end)

        quote do
          {unquote(name), unquote(version), unquote(dep_opts)}
        end
      else
        {:__block__, [],
         [
           {{:__block__, [], [name]}, {:__block__, [], [version]}}
         ]}
      end

    igniter
    |> Igniter.update_elixir_file("mix.exs", fn zipper ->
      with {:ok, zipper} <- Igniter.Code.Module.move_to_module_using(zipper, Mix.Project),
           {:ok, zipper} <- Igniter.Code.Function.move_to_defp(zipper, :deps, 0) do
        case igniter.assigns[:igniter_exs][:deps_location] || :last_list_literal do
          {m, f, a} ->
            case apply(m, f, [a] ++ [igniter, zipper]) do
              {:ok, zipper} ->
                add_to_deps_list(zipper, name, quoted, opts)

              :error ->
                {error_tag,
                 """
                 Could not add dependency #{inspect({name, version})}

                 #{inspect(m)}.#{f}/#{Enum.count(a) + 2} did not find a deps location

                 Please add the dependency manually.
                 """}
            end

          {:variable, name} ->
            with {:ok, zipper} <-
                   Igniter.Code.Common.move_to(
                     zipper,
                     &Igniter.Code.Common.variable_assignment?(&1, name)
                   ),
                 {:ok, zipper} <- Igniter.Code.Function.move_to_nth_argument(zipper, 1),
                 true <- Igniter.Code.List.list?(zipper) do
              add_to_deps_list(zipper, name, quoted, opts)
            else
              _ ->
                {error_tag,
                 """
                 Could not add dependency #{inspect({name, version})}

                 `deps/0` does not contain an assignment of the `#{name}` variable to a literal list

                 Please add the dependency manually.
                 """}
            end

          :last_list_literal ->
            zipper = Zipper.rightmost(zipper)

            if Igniter.Code.List.list?(zipper) do
              add_to_deps_list(zipper, name, quoted, opts)
            else
              {error_tag,
               """
               Could not add dependency #{inspect({name, version})}

               `deps/0` does not end in a list literal that can be added to.

               Please add the dependency manually.
               """}
            end
        end
      else
        _ ->
          {error_tag,
           """
           Could not add dependency #{inspect({name, version})}

           `mix.exs` file does not contain a `deps/0` function.

           Please add the dependency manually.
           """}
      end
    end)
  end

  defp add_to_deps_list(zipper, name, quoted, opts) do
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
  end

  @doc false
  def determine_dep_opts(requirement) do
    case String.split(requirement, "#", trim: true, parts: 2) do
      [_] ->
        []

      [_, opt_string] ->
        opt_string
        |> URI.decode_query()
        |> Enum.reduce([], fn {key, value}, acc ->
          case {key, value} do
            {"app", "false"} -> Keyword.put(acc, :app, false)
            {"env", env} -> Keyword.put(acc, :env, String.to_atom(env))
            {"compile", compile} -> Keyword.put(acc, :compile, compile)
            # skipping only now since it has special handling
            # {"only", only} -> Keyword.put(acc, :only, {:code, only})
            {"targets", targets} -> Keyword.put(acc, :targets, {:code, targets})
            {"override", "true"} -> Keyword.put(acc, :override, true)
            {"manager", manager} -> Keyword.put(acc, :manager, String.to_atom(manager))
            {"runtime", "false"} -> Keyword.put(acc, :runtime, false)
            {"system_env", system_env} -> Keyword.put(acc, :system_env, {:code, system_env})
            # Arbitrary options are used by Nerves for example:
            # {:nerves_system_rpi4, path: "foo", nerves: [compile: true]}
            {key, value} -> Keyword.put(acc, String.to_atom(key), {:code, value})
          end
        end)
    end
  end

  @doc false
  def determine_dep_type_and_version(requirement) do
    # Drop any fragment-style options
    requirement = String.split(requirement, "#") |> hd()

    case String.split(requirement, "@", trim: true, parts: 2) do
      [package] ->
        if Regex.match?(~r/^[a-z][a-z0-9_]*$/, package) do
          {:ok, _} = Application.ensure_all_started(:req)

          case Req.get("https://hex.pm/api/packages/#{package}",
                 headers: [{"User-Agent", "igniter-installer"}]
               ) do
            {:ok, %{body: %{"releases" => releases} = body}} ->
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
