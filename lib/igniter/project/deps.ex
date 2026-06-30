# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Igniter.Project.Deps do
  @moduledoc "Codemods and utilities for managing dependencies declared in mix.exs"
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
  - `:on_exists` - The action to take if the dep is already present
    - `:overwrite` (default) - Overwrites with the new depenency
    - `:skip` - Skips adding the dependency
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

      {:ok, current_source} ->
        if opts[:on_exists] == :skip do
          igniter
        else
          desired =
            if opts[:dep_opts] do
              Code.eval_string(
                "{#{inspect(name)}, #{inspect(version)}, #{inspect(opts[:dep_opts])}}"
              )
              |> elem(0)
            else
              Code.eval_string("{#{inspect(name)}, #{inspect(version)}}") |> elem(0)
            end

          current = Code.eval_string(current_source) |> elem(0)

          {desired, current} =
            case {desired, current} do
              {{da, db}, {ca, cb, []}} ->
                {{da, db}, {ca, cb}}

              {{da, db, []}, {ca, cb}} ->
                {{da, db}, {ca, cb}}

              {desired, current} ->
                {desired, current}
            end

          if desired == current do
            if opts[:notify_on_present?] do
              Mix.shell().info(
                "Dependency #{name} is already in mix.exs with the desired version. Skipping."
              )
            end

            igniter
          else
            desired_display = dep_declaration_string(name, version, opts[:dep_opts])
            current_display = String.trim(current_source)

            if opts[:yes?] ||
                 Igniter.Util.IO.yes?("""
                 Dependency #{name} is already in mix.exs. Should we replace it?

                 Desired: `#{desired_display}`
                 Found: `#{current_display}`
                 """) do
              do_add_dependency(igniter, name, version, opts)
            else
              igniter
            end
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

        {:variable, var_name} ->
          with {:ok, zipper} <-
                 Igniter.Code.Common.move_to(
                   zipper,
                   &Igniter.Code.Common.variable_assignment?(&1, var_name)
                 ),
               {:ok, zipper} <- Igniter.Code.Function.move_to_nth_argument(zipper, 1),
               true <- Igniter.Code.List.list?(zipper) do
            get_dep_declaration(zipper, name)
          else
            _ ->
              {:error,
               """
               Could not get dependency #{inspect(name)}

               `deps/0` does not contain an assignment of the `#{var_name}` variable to a literal list

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

          {:variable, var_name} ->
            with {:ok, zipper} <-
                   Igniter.Code.Common.move_to(
                     zipper,
                     &Igniter.Code.Common.variable_assignment?(&1, var_name)
                   ),
                 {:ok, zipper} <- Igniter.Code.Function.move_to_nth_argument(zipper, 1),
                 true <- Igniter.Code.List.list?(zipper) do
              remove_from_deps_list(zipper, name)
            else
              _ ->
                {:warning,
                 """
                 Could not remove dependency #{inspect(name)}

                 `deps/0` does not contain an assignment of the `#{var_name}` variable to a literal list

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

  defp dep_declaration_string(name, version, dep_opts) do
    quoted =
      if dep_opts do
        quote do
          {unquote(name), unquote(version), unquote(dep_opts)}
        end
      else
        {:__block__, [],
         [
           {{:__block__, [], [name]}, {:__block__, [], [version]}}
         ]}
      end

    quoted
    |> Sourceror.to_string()
    |> String.trim()
  end

  defp do_add_dependency(igniter, name, version, opts) do
    error_tag =
      if opts[:error?] do
        :error
      else
        :warning
      end

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

          {:variable, var_name} ->
            with {:ok, zipper} <-
                   Igniter.Code.Common.move_to(
                     zipper,
                     &Igniter.Code.Common.variable_assignment?(&1, var_name)
                   ),
                 {:ok, zipper} <- Igniter.Code.Function.move_to_nth_argument(zipper, 1),
                 true <- Igniter.Code.List.list?(zipper) do
              add_to_deps_list(zipper, name, quoted, opts)
            else
              _ ->
                {error_tag,
                 """
                 Could not add dependency #{inspect({name, version})}

                 `deps/0` does not contain an assignment of the `#{var_name}` variable to a literal list

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
  def determine_dep_type_and_version!(requirement, options \\ []) do
    [package | maybe_version] = String.split(requirement, "@", trim: true, parts: 2)

    {package, opts} =
      case String.split(package, "/", parts: 2) do
        [org, package] -> {package, organization: org}
        [package] -> {package, []}
      end

    {package, opts} =
      case String.split(package, ".", parts: 2) do
        [repo, package] -> {package, Keyword.put(opts, :repo, repo)}
        [package] -> {package, opts}
      end

    argv = Keyword.get(options, :argv)

    case maybe_version do
      [] ->
        with {:ok, version} <- resolve_latest_hex_version(package, opts, argv) do
          {version, []}
        end

      ["git:" <> requirement] ->
        {nil, git_dep_opts(requirement, :git)}

      ["github:" <> requirement] ->
        {nil, git_dep_opts(requirement, :github)}

      ["path:" <> requirement] ->
        {nil, path: requirement, override: true}

      [version] ->
        case Version.parse(version) do
          {:ok, version} ->
            {"== #{version}", []}

          _ ->
            case Igniter.Util.Version.version_string_to_general_requirement(version) do
              {:ok, requirement} ->
                {requirement, []}

              _ ->
                :error
            end
        end

      _ ->
        :error
    end
    |> case do
      {version, additional_opts} ->
        to_dependency_spec(package, version, additional_opts ++ opts)

      :error ->
        if opts[:repo] do
          Mix.raise("""
          Failed to automatically determine latest version for `#{requirement}`

          Private repositories (like `#{opts[:repo]}`) do not always expose APIs that allow
          us to determine the latest verison. This means you may need to specify a version manually.

          For example:

              mix igniter.install #{requirement}@1.0

          Please see the documentation of the package you are trying to install for more information.
          """)
        else
          if opts[:organization] do
            Mix.raise("""
            Failed to automatically determine latest version for `#{requirement}`.

            You may need to specify a version manually. For example:

              mix igniter.install #{requirement}@1.0

            Please see the documentation of the package you are trying to install for more information.
            """)
          else
            Mix.raise("""
            Failed to automatically determine latest version for `#{requirement}`

            This may mean that the package `#{package}` is not available on hex, or that you are missing some extra information.

            You may need to specify a version manually. For example:

              mix igniter.install #{requirement}@1.0

            If it is a private package from a hexpm organization, include that organization.

                mix igniter.install org/#{requirement}

            Or if it is a package from a private repository, include the repository name.

                mix igniter.install repo.#{requirement}
            """)
          end
        end
    end
  end

  defp to_dependency_spec(package, version, opts)
  defp to_dependency_spec(package, version, []), do: {String.to_atom(package), version}
  defp to_dependency_spec(package, nil, opts), do: {String.to_atom(package), opts}
  defp to_dependency_spec(package, version, opts), do: {String.to_atom(package), version, opts}

  defp git_dep_opts(string, kind) do
    case String.split(string, "@", trim: true, parts: 2) do
      [git_dep, ref] ->
        [{kind, git_dep}, {:ref, ref}, {:override, true}]

      [git_dep] ->
        [{kind, git_dep}, {:override, true}]
    end
  end

  defp fetch_latest_version(package, opts) do
    if Regex.match?(~r/^[a-z][a-z0-9_]*$/, package) do
      {:ok, _} = Application.ensure_all_started(:req)

      with {:ok, url, headers} <-
             fetch_hex_api_url_and_headers(package, opts),
           {:ok, %{body: %{"releases" => releases} = body}} <-
             Req.get(url,
               headers: headers
             ),
           %{"version" => version} <- first_non_rc_version_or_first_version(releases, body) do
        {:ok, Igniter.Util.Version.version_string_to_general_requirement!(version)}
      else
        _ -> :error
      end
    else
      :error
    end
  rescue
    _ ->
      :error
  end

  defp resolve_latest_hex_version(package, hex_opts, argv) when is_list(hex_opts) do
    if is_list(argv) do
      fetch_latest_hex_version_with_maybe_confirm(package, hex_opts, argv)
    else
      fetch_latest_version(package, hex_opts)
    end
  end

  defp fetch_latest_hex_version_with_maybe_confirm(package, hex_opts, argv)
       when is_binary(package) and is_list(hex_opts) and is_list(argv) do
    if Regex.match?(~r/^[a-z][a-z0-9_]*$/, package) do
      case fetch_hex_latest_bundle_for_confirm(package, hex_opts) do
        {:ok, raw_version, popup_fields} ->
          auto_yes? = not Igniter.Mix.Task.tty?() or "--yes" in argv

          unless auto_yes? do
            Mix.shell().info("\n" <> format_hex_confirmation_from_popup_fields(popup_fields))

            unless Igniter.Util.IO.yes?("Is this correct?") do
              exit({:shutdown, 1})
            end
          end

          {:ok, Igniter.Util.Version.version_string_to_general_requirement!(raw_version)}

        :error ->
          :error
      end
    else
      :error
    end
  rescue
    _ ->
      :error
  end

  defp fetch_hex_latest_bundle_for_confirm(package, opts)
       when is_binary(package) and is_list(opts) do
    {:ok, _} = Application.ensure_all_started(:req)

    with {:ok, package_api_url, headers} <-
           fetch_hex_package_url_maybe(package, opts),
         {:ok, body} <- req_hex_package_json(package_api_url, headers),
         {:ok, chosen} <- hex_pick_latest_release(body),
         {:ok, version_string} <- hex_resolve_release_version_string(chosen) do
      release_detail =
        case req_hex_release_json(package_api_url, version_string, headers) do
          {:ok, %{} = rb} -> rb
          _ -> %{}
        end

      release_body = Map.merge(hex_string_key_map(chosen), release_detail)

      {:ok, version_string, hex_install_popup_fields(package, body, release_body)}
    else
      _ -> :error
    end
  end

  defp hex_string_key_map(map) when is_map(map) do
    for {k, v} <- map, into: %{} do
      {if(is_atom(k), do: Atom.to_string(k), else: k), v}
    end
  end

  defp hex_resolve_release_version_string(%{} = chosen) do
    case chosen["version"] || chosen[:version] do
      v when is_binary(v) and v != "" -> {:ok, v}
      v when is_atom(v) -> {:ok, Atom.to_string(v)}
      _ -> :error
    end
  end

  defp hex_resolve_release_version_string(_), do: :error

  defp fetch_hex_package_url_maybe(package, opts) do
    {:ok, url, hdrs} = fetch_hex_api_url_and_headers(package, opts)
    {:ok, url, hdrs}
  rescue
    _ -> :error
  end

  defp req_hex_package_json(package_api_url, headers) do
    case Req.get(package_api_url, headers: headers) do
      {:ok, %{status: 200, body: %{} = response_body}} ->
        {:ok, response_body}

      _ ->
        :error
    end
  end

  defp hex_pick_latest_release(body) do
    case body["releases"] do
      [_ | _] = releases ->
        case first_non_rc_version_or_first_version(releases, body) do
          nil -> :error
          chosen -> {:ok, chosen}
        end

      _ ->
        :error
    end
  end

  defp req_hex_release_json(package_api_url, version_string, headers) do
    rel_url = hex_release_api_url(package_api_url, version_string)

    case Req.get(rel_url, headers: headers) do
      {:ok, %{status: 200, body: %{} = rb}} -> {:ok, rb}
      _ -> :error
    end
  end

  defp format_hex_confirmation_from_popup_fields(fields) when is_map(fields) do
    """
    You are installing the package "#{fields.package}":

    Description:       #{fields.description}
    Current version:   #{fields.version} (released #{fields.release_date})
    hex.pm authors:    #{fields.hex_authors}
    hex.pm publishers: #{fields.hex_publishers}
    Dependencies:      #{fields.deps_list}
    Downloads:         #{fields.downloads_this_version} (this version), #{fields.downloads_last_seven_days} (last 7 days), #{fields.downloads_all_time} (all time)

    """
  end

  defp hex_install_popup_fields(package_atom_string, pkg_body, release_body) do
    version = release_body["version"]
    reqs = Map.get(release_body, "requirements") || %{}

    deps_list =
      reqs |> Map.keys() |> Enum.sort() |> Enum.join(", ")

    owners =
      (pkg_body["owners"] || []) |> Enum.map(&hex_popup_user_label/1) |> Enum.reject(&is_nil/1)

    publisher_accounts =
      case release_body["publisher"] do
        %{} = pu ->
          List.wrap(hex_popup_user_label(pu))

        _ ->
          owners
      end

    downloads_pkg = pkg_body["downloads"] || %{}

    %{
      package: package_atom_string,
      description: hex_popup_description(pkg_body),
      version: hex_popup_optional_text(version),
      release_date: hex_popup_inserted_at_date(release_body["inserted_at"]),
      hex_authors: hex_popup_join_user_list(owners),
      hex_publishers: hex_popup_join_user_list(publisher_accounts),
      deps_list: if(deps_list == "", do: hex_popup_na(), else: deps_list),
      downloads_this_version: hex_popup_format_download(release_body["downloads"]),
      downloads_last_seven_days: hex_popup_format_download(downloads_pkg["week"]),
      downloads_all_time: hex_popup_format_download(downloads_pkg["all"])
    }
  end

  defp hex_popup_na, do: "N/A"

  defp hex_popup_optional_text(term) when term in [nil, ""], do: hex_popup_na()

  defp hex_popup_optional_text(s) when is_binary(s), do: s

  defp hex_popup_optional_text(v) when is_atom(v),
    do: v |> Atom.to_string() |> hex_popup_optional_text()

  defp hex_popup_optional_text(n) when is_integer(n), do: Integer.to_string(n)

  defp hex_popup_optional_text(n) when is_float(n), do: Float.to_string(n)

  defp hex_popup_optional_text(_), do: hex_popup_na()

  defp hex_release_api_url(package_api_url, version) do
    enc = URI.encode(version, &URI.char_unreserved?/1)
    package_api_url <> "/releases/" <> enc
  end

  defp hex_popup_description(pkg_body) do
    case get_in(pkg_body, ["meta", "description"]) do
      d when is_binary(d) -> String.replace(d, "\n", " ")
      _ -> hex_popup_na()
    end
  end

  defp hex_popup_inserted_at_date(str) when is_binary(str) do
    case String.split(str, "T", parts: 2) do
      [date | _] when date != "" -> date
      _ -> hex_popup_na()
    end
  rescue
    _ -> hex_popup_na()
  end

  defp hex_popup_inserted_at_date(_), do: hex_popup_na()

  defp hex_popup_user_label(%{"username" => u}) when is_binary(u), do: u
  defp hex_popup_user_label(%{"username" => u}) when is_atom(u), do: Atom.to_string(u)
  defp hex_popup_user_label(_), do: nil

  defp hex_popup_join_user_list(users) when is_list(users) do
    case users |> Enum.reject(&(&1 in [nil, ""])) |> Enum.uniq() do
      [] -> hex_popup_na()
      xs -> Enum.join(xs, ", ")
    end
  end

  defp hex_popup_format_download(n) when is_integer(n),
    do: hex_popup_space_int(abs(n)) |> maybe_neg_prefix(n)

  defp hex_popup_format_download(_),
    do: hex_popup_na()

  defp maybe_neg_prefix(s, int) when int < 0, do: "-" <> s
  defp maybe_neg_prefix(s, _), do: s

  defp hex_popup_space_int(abs_int) when is_integer(abs_int) do
    abs_int |> Integer.to_string() |> String.replace(~r/\B(?=(\d{3})+(?!\d))/, " ")
  end

  def fetch_hex_api_url_and_headers(package, opts) do
    default_headers = [
      {"User-Agent", "igniter-installer"},
      {
        "Accept",
        "application/json"
      }
    ]

    cond do
      repo = opts[:repo] ->
        repo =
          :repos
          |> fetch_hex_state()
          |> Map.get(repo)
          |> Kernel.||(
            raise """
            No repository found for #{opts[:repo]}. Perhaps you missed a setup step, like below?

                mix hex.repo add ...
            """
          )

        fetch_public_package_url(
          repo.url,
          package,
          default_headers ++ auth_headers(key: repo.auth_key)
        )

      org = opts[:organization] ->
        fetch_org_package_url("https://hex.pm/api", package, org, default_headers)

      true ->
        fetch_public_package_url(
          "https://hex.pm/api",
          package,
          default_headers
        )
    end
  end

  defp fetch_public_package_url(api_url, package, default_headers) do
    {:ok, "#{api_url}/packages/#{package}", default_headers}
  end

  defp fetch_org_package_url(api_url, package, org, default_headers) do
    auth = get_hex_auth()

    {:ok, "#{api_url}/repos/#{org}/packages/#{package}", auth_headers(auth) ++ default_headers}
  end

  defp get_hex_auth do
    api_key_write_unencrypted = fetch_hex_state(:api_key_write_unencrypted)
    api_key_read = fetch_hex_state(:api_key_read)

    cond do
      api_key_write_unencrypted ->
        [key: api_key_write_unencrypted]

      api_key_read ->
        [key: api_key_read]

      true ->
        raise """
        No authentication key found for api:read.

        Please run `mix hex.user auth` to authenticate with Hex and ensure that the user is a member of the organization.
        """
    end
  end

  defp auth_headers(opts) do
    cond do
      opts[:key] ->
        [{"authorization", opts[:key]}]

      opts[:user] && opts[:pass] ->
        base64 = :base64.encode(opts[:user] <> ":" <> opts[:pass])
        [{"authorization", "Basic " <> base64}]

      true ->
        []
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

  # This is a hack. I've done this because actually talking to hex was causing
  # errors w/ the type system on 1.16, and including `:hex` in the apps list
  # caused its own kind of strange compilation errors.
  defp fetch_hex_state(key) do
    Agent.get(Hex.State, fn state ->
      case Map.fetch(state, key) do
        {:ok, {_source, value}} ->
          value

        _ ->
          nil
      end
    end)
  end
end
