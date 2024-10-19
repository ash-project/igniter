defmodule Igniter.Project.Module do
  @moduledoc "Codemods and utilities for interacting with modules"

  require Igniter.Code.Common
  alias Igniter.Code.Common
  alias Sourceror.Zipper
  require Logger

  @typedoc """
  Placement instruction for a module.

  - `:source_folder` - The first source folder of the project
  - `{:source_folder, path}` - The selected source folder, i.e `"lib"`
  - `:test` - Creating a test file
  - `:test_support` - Creating a test support file
  """
  @type location_type :: :source_folder | {:source_folder, String.t()} | :test | :test_support

  @doc """
  Determines where a module should be placed in a project.
  """
  @spec proper_location(Igniter.t(), module(), location_type()) :: String.t()
  def proper_location(igniter, module_name, type \\ :source_folder) do
    type =
      case type do
        :source_folder ->
          igniter
          |> Igniter.Project.IgniterConfig.get(:source_folders)
          |> Enum.at(0)
          |> then(&{:source_folder, &1})

        :test_support ->
          {:source_folder, "test/support"}

        type ->
          type
      end

    do_proper_location(igniter, module_name, type)
  end

  @doc "Given a suffix, returns a module name with the prefix of the current project."
  @spec module_name(Igniter.t(), String.t()) :: module()
  def module_name(igniter, suffix) do
    Module.concat(module_name_prefix(igniter), suffix)
  end

  @doc "The module name prefix based on the mix project's module name"
  @spec module_name_prefix(Igniter.t()) :: module()
  def module_name_prefix(igniter) do
    zipper =
      igniter
      |> Igniter.include_existing_file("mix.exs")
      |> Map.get(:rewrite)
      |> Rewrite.source!("mix.exs")
      |> Rewrite.Source.get(:quoted)
      |> Sourceror.Zipper.zip()

    with {:ok, zipper} <- Igniter.Code.Module.move_to_defmodule(zipper),
         {:ok, zipper} <- Igniter.Code.Function.move_to_nth_argument(zipper, 0) do
      case Igniter.Code.Common.expand_alias(zipper) do
        %Zipper{node: module_name} when is_atom(module_name) ->
          module_name
          |> Module.split()
          |> :lists.droplast()
          |> Module.concat()

        %Zipper{node: {:__aliases__, _, parts}} ->
          parts
          |> :lists.droplast()
          |> Module.concat()
      end
    else
      _ ->
        raise """
        Failed to parse the module name from mix.exs.

        Please ensure that you are defining a Mix.Project module in your mix.exs file.
        """
    end
  end

  @doc """
  Finds a module, raising an error if its not found.

  See `find_module/2` for more information.
  """
  @spec find_module!(Igniter.t(), module()) ::
          {Igniter.t(), Rewrite.Source.t(), Zipper.t()} | no_return
  def find_module!(igniter, module_name) do
    case find_module(igniter, module_name) do
      {:ok, {igniter, source, zipper}} ->
        {igniter, source, zipper}

      {:error, _igniter} ->
        raise "Could not find module `#{inspect(module_name)}`"
    end
  end

  @doc """
  Finds a module and updates its contents wherever it is.

  If the module does not yet exist, it is created with the provided contents. In that case,
  the path is determined with `Igniter.Code.Module.proper_location/2`, but may optionally be overwritten with options below.

  # Options

  - `:path` - Path where to create the module, relative to the project root. Default: `nil` (uses `:kind` to determine the path).
  """
  def find_and_update_or_create_module(igniter, module_name, contents, updater, opts \\ [])

  def find_and_update_or_create_module(
        igniter,
        module_name,
        contents,
        updater,
        opts
      )
      when is_list(opts) do
    case find_and_update_module(igniter, module_name, updater) do
      {:ok, igniter} ->
        igniter

      {:error, igniter} ->
        create_module(igniter, module_name, contents, opts)
    end
  end

  def find_and_update_or_create_module(
        igniter,
        module_name,
        contents,
        updater,
        path
      )
      when is_binary(path) do
    Logger.warning("You should use `opts` instead of `path` and pass `path` as a keyword.")
    find_and_update_or_create_module(igniter, module_name, contents, updater, path: path)
  end

  @doc """
  Creates a new file & module in its appropriate location.

  ## Options

  - `:location` - A location type. See `t:location_type` for more.
  """
  def create_module(igniter, module_name, contents, opts \\ []) do
    contents =
      """
      defmodule #{inspect(module_name)} do
        #{contents}
      end
      """

    location =
      case Keyword.get(opts, :path, nil) do
        nil ->
          proper_location(igniter, module_name, opts[:location] || :source_folder)

        path ->
          path
      end

    Igniter.create_new_file(igniter, location, contents)
  end

  @doc "Checks if a module is defined somewhere in the project. The returned igniter should not be discarded."
  @deprecated "Use `module_exists/2` instead."
  def module_exists?(igniter, module_name) do
    module_exists(igniter, module_name)
  end

  @doc "Checks if a module is defined somewhere in the project. The returned igniter should not be discarded."
  @spec module_exists(Igniter.t(), module()) :: {boolean(), Igniter.t()}
  def module_exists(igniter, module_name) do
    case find_module(igniter, module_name) do
      {:ok, {igniter, _, _}} -> {true, igniter}
      {:error, igniter} -> {false, igniter}
    end
  end

  @doc "Finds a module and updates its contents. Raises an error if it doesn't exist"
  @spec find_and_update_module!(Igniter.t(), module(), (Zipper.t() -> {:ok, Zipper.t()} | :error)) ::
          Igniter.t()
  def find_and_update_module!(igniter, module_name, updater) do
    case find_and_update_module(igniter, module_name, updater) do
      {:ok, igniter} -> igniter
      {:error, _igniter} -> raise "Could not find module #{inspect(module_name)}"
    end
  end

  @doc "Finds a module and updates its contents. Returns `{:error, igniter}` if the module could not be found. Do not discard this igniter."
  @spec find_and_update_module(Igniter.t(), module(), (Zipper.t() -> {:ok, Zipper.t()} | :error)) ::
          {:ok, Igniter.t()} | {:error, Igniter.t()}
  def find_and_update_module(igniter, module_name, updater) do
    case find_module(igniter, module_name) do
      {:ok, {igniter, source, zipper}} ->
        case Common.move_to_do_block(zipper) do
          {:ok, zipper} ->
            case updater.(zipper) do
              {:ok, zipper} ->
                new_quoted =
                  zipper
                  |> Zipper.topmost()
                  |> Zipper.node()

                new_source = Rewrite.Source.update(source, :quoted, new_quoted)
                {:ok, %{igniter | rewrite: Rewrite.update!(igniter.rewrite, new_source)}}

              {:error, error} ->
                {:ok, Igniter.add_issue(igniter, error)}

              {:warning, error} ->
                {:ok, Igniter.add_warning(igniter, error)}
            end

          _ ->
            {:error, igniter}
        end

      {:error, igniter} ->
        {:error, igniter}
    end
  end

  @spec find_all_matching_modules(igniter :: Igniter.t(), (module(), Zipper.t() -> boolean)) ::
          {Igniter.t(), [module()]}
  def find_all_matching_modules(igniter, predicate) do
    igniter =
      igniter
      |> Igniter.include_all_elixir_files()

    matching_modules =
      igniter
      |> Map.get(:rewrite)
      |> Enum.filter(&match?(%Rewrite.Source{filetype: %Rewrite.Source.Ex{}}, &1))
      |> Task.async_stream(
        fn source ->
          source
          |> Rewrite.Source.get(:quoted)
          |> Zipper.zip()
          |> Zipper.traverse([], fn zipper, acc ->
            case zipper.node do
              {:defmodule, _, [_, _]} ->
                {:ok, mod_zipper} = Igniter.Code.Function.move_to_nth_argument(zipper, 0)

                module_name =
                  mod_zipper
                  |> Igniter.Code.Common.expand_alias()
                  |> Zipper.node()
                  |> Igniter.Project.Module.to_module_name()

                with module_name when not is_nil(module_name) <- module_name,
                     {:ok, do_zipper} <- Igniter.Code.Common.move_to_do_block(zipper),
                     true <- predicate.(module_name, do_zipper) do
                  {zipper, [module_name | acc]}
                else
                  _ ->
                    {zipper, acc}
                end

              _ ->
                {zipper, acc}
            end
          end)
          |> elem(1)
        end,
        timeout: :infinity
      )
      |> Enum.flat_map(fn {:ok, v} ->
        v
      end)
      |> Enum.uniq()

    {igniter, matching_modules}
  end

  @doc """
  Finds a module, returning a new igniter, and the source and zipper location. This new igniter should not be discarded.

  In general, you should not use the returned source and zipper to update the module, instead, use this to interrogate
  the contents or source in some way, and then call `find_and_update_module/3` with a function to perform an update.
  """
  @spec find_module(Igniter.t(), module()) ::
          {:ok, {Igniter.t(), Rewrite.Source.t(), Zipper.t()}} | {:error, Igniter.t()}
  def find_module(igniter, module_name) do
    igniter = Igniter.include_all_elixir_files(igniter)

    check_first =
      if Code.ensure_loaded?(module_name) do
        if source = module_name.module_info()[:compile][:source] do
          Path.relative_to_cwd(List.to_string(source))
        end
      end

    with check_first when not is_nil(check_first) <- check_first,
         {:ok, source} <- Rewrite.source(igniter.rewrite, check_first),
         {:ok, zipper} <-
           source
           |> Rewrite.Source.get(:quoted)
           |> Zipper.zip()
           |> Igniter.Code.Module.move_to_defmodule(module_name) do
      {:ok, {igniter, source, zipper}}
    else
      _ ->
        igniter
        |> Map.get(:rewrite)
        |> Enum.filter(&match?(%Rewrite.Source{filetype: %Rewrite.Source.Ex{}}, &1))
        |> Task.async_stream(
          fn source ->
            {source
             |> Rewrite.Source.get(:quoted)
             |> Zipper.zip()
             |> Igniter.Code.Module.move_to_defmodule(module_name), source}
          end,
          timeout: :infinity
        )
        |> Enum.find_value({:error, igniter}, fn
          {:ok, {{:ok, zipper}, source}} ->
            {:ok, {igniter, source, zipper}}

          _other ->
            false
        end)
    end
  end

  @doc false
  def move_files(igniter, opts \\ []) do
    module_location_config = Igniter.Project.IgniterConfig.get(igniter, :module_location)
    dont_move_files = Igniter.Project.IgniterConfig.get(igniter, :dont_move_files)

    igniter =
      if opts[:move_all?] do
        Igniter.include_all_elixir_files(igniter)
      else
        igniter
      end

    igniter.rewrite
    |> Stream.filter(&(Path.extname(&1.path) in [".ex", ".exs"]))
    |> Stream.reject(&non_movable_file?(&1.path, dont_move_files))
    |> Enum.reduce(igniter, fn source, igniter ->
      zipper =
        source
        |> Rewrite.Source.get(:quoted)
        |> Zipper.zip()

      with {:ok, zipper} <- Igniter.Code.Module.move_to_defmodule(zipper),
           {:ok, zipper} <- Igniter.Code.Function.move_to_nth_argument(zipper, 0),
           module <-
             zipper
             |> Igniter.Code.Common.expand_alias()
             |> Zipper.node(),
           module when not is_nil(module) <- to_module_name(module),
           new_path when not is_nil(new_path) <-
             should_move_file_to(igniter, source, module, module_location_config, opts) do
        Igniter.move_file(igniter, source.path, new_path, error_if_exists?: false)
      else
        _ ->
          igniter
      end
    end)
  end

  defp non_movable_file?(path, dont_move_files) do
    Enum.any?(dont_move_files, fn
      exclusion_pattern when is_binary(exclusion_pattern) ->
        path == exclusion_pattern

      exclusion_pattern when is_struct(exclusion_pattern, Regex) ->
        Regex.match?(exclusion_pattern, path)
    end)
  end

  defp should_move_file_to(igniter, source, module, module_location_config, opts) do
    paths_created =
      igniter.rewrite
      |> Enum.filter(fn source ->
        Rewrite.Source.from?(source, :string)
      end)
      |> Enum.map(& &1.path)

    split_path =
      source.path
      |> Path.relative_to_cwd()
      |> Path.split()

    igniter
    |> Igniter.Project.IgniterConfig.get(:source_folders)
    |> Enum.filter(fn source_folder ->
      List.starts_with?(split_path, Path.split(source_folder))
    end)
    |> Enum.max_by(
      fn source_folder ->
        source_folder
        |> Path.split()
        |> Enum.zip(split_path)
        |> Enum.take_while(fn {l, r} -> l == r end)
        |> Enum.count()
      end,
      fn -> nil end
    )
    |> case do
      nil ->
        if Enum.at(split_path, 0) == "test" &&
             String.ends_with?(source.path, "_test.exs") do
          {:ok, proper_location(igniter, module, :test), :test}
        else
          :error
        end

      source_folder ->
        {:ok, proper_location(igniter, module, {:source_folder, source_folder}),
         {:source_folder, source_folder}}
    end
    |> case do
      :error ->
        nil

      {:ok, proper_location, location_type} ->
        case module_location_config do
          :inside_matching_folder ->
            {[filename, folder], rest} =
              proper_location
              |> Path.split()
              |> Enum.reverse()
              |> Enum.split(2)

            inside_matching_folder =
              [filename, Path.rootname(filename), folder]
              |> Enum.concat(rest)
              |> Enum.reverse()
              |> Path.join()

            inside_matching_folder_dirname = Path.dirname(inside_matching_folder)

            just_created_folder? =
              Enum.any?(paths_created, fn path ->
                List.starts_with?(Path.split(path), Path.split(inside_matching_folder_dirname))
              end)

            should_use_inside_matching_folder? =
              if opts[:move_all?] do
                dir?(igniter, inside_matching_folder_dirname) || just_created_folder?
              else
                source.path == proper_location(igniter, module, location_type) &&
                  !dir?(igniter, inside_matching_folder_dirname) && just_created_folder?
              end

            if should_use_inside_matching_folder? do
              inside_matching_folder
            else
              proper_location
            end

          :outside_matching_folder ->
            if opts[:move_all?] || Rewrite.Source.from?(source, :string) do
              proper_location
            end
        end
    end
  end

  defp dir?(igniter, folder) do
    if igniter.assigns[:test_mode?] do
      igniter.assigns[:test_files]
      |> Map.keys()
      |> Enum.any?(fn file_path ->
        List.starts_with?(Path.split(file_path), Path.split(folder))
      end)
    else
      File.dir?(folder)
    end
  end

  @doc false
  def to_module_name({:__aliases__, _, parts}), do: Module.concat(parts)
  def to_module_name(value) when is_atom(value) and not is_nil(value), do: value
  def to_module_name(_), do: nil

  defp do_proper_location(igniter, module_name, kind) do
    path =
      module_name
      |> Module.split()
      |> case do
        ["Mix", "Tasks" | rest] ->
          suffix =
            rest
            |> Enum.map(&to_string/1)
            |> Enum.map_join(".", &Macro.underscore/1)

          ["mix", "tasks", suffix]

        _other ->
          modified_module_name =
            case kind do
              :test ->
                string_module = to_string(module_name)

                if String.ends_with?(string_module, "Test") do
                  Module.concat([String.slice(string_module, 0..-5//1)])
                else
                  module_name
                end

              _ ->
                module_name
            end

          module_to_path(igniter, modified_module_name, module_name)
      end

    last = List.last(path)
    leading = :lists.droplast(path)

    case kind do
      :test ->
        if String.ends_with?(last, "_test") do
          Path.join(["test" | leading] ++ ["#{last}.exs"])
        else
          Path.join(["test" | leading] ++ ["#{last}_test.exs"])
        end

      {:source_folder, "test/support"} ->
        case leading do
          [] ->
            Path.join(["test/support", "#{last}.ex"])

          [_prefix | leading_rest] ->
            Path.join(["test/support" | leading_rest] ++ ["#{last}.ex"])
        end

      {:source_folder, source_folder} ->
        Path.join([source_folder | leading] ++ ["#{last}.ex"])
    end
  end

  defp module_to_path(igniter, module, original) do
    Enum.reduce_while(
      igniter.assigns[:igniter_exs][:extensions] || [],
      :error,
      fn {extension, opts}, status ->
        case extension.proper_location(igniter, module, opts) do
          :error ->
            {:cont, status}

          :keep ->
            {:cont, :keep}

          {:ok, path} ->
            {:halt, {:ok, path}}
        end
      end
    )
    |> case do
      :keep ->
        case find_module(igniter, original) do
          {:ok, {_, source, _}} ->
            split_path =
              source.path
              |> Path.rootname(".ex")
              |> Path.rootname(".exs")
              |> Path.split()

            igniter
            |> Igniter.Project.IgniterConfig.get(:source_folders)
            |> Enum.concat(["test"])
            |> Enum.uniq()
            |> Enum.map(&Path.split/1)
            |> Enum.sort_by(&(-length(&1)))
            |> Enum.find(fn source_folder ->
              List.starts_with?(split_path, Path.split(source_folder))
            end)
            |> case do
              nil ->
                default_location(module)

              source_path ->
                Enum.drop(split_path, Enum.count(source_path))
            end

          _ ->
            default_location(module)
        end

      :error ->
        default_location(module)

      {:ok, path} ->
        path
        |> Path.rootname(".ex")
        |> Path.rootname(".exs")
        |> Path.split()
    end
  end

  defp default_location(module) do
    module
    |> Module.split()
    |> Enum.map(&to_string/1)
    |> Enum.map(&Macro.underscore/1)
  end

  @doc "Parses a string into a module name"
  @spec parse(String.t()) :: module()
  def parse(module_name) do
    module_name
    |> String.split(".")
    |> Module.concat()
  end
end
