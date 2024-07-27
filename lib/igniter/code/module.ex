defmodule Igniter.Code.Module do
  @moduledoc "Utilities for working with Elixir modules"
  require Igniter.Code.Common
  alias Igniter.Code.Common
  alias Sourceror.Zipper

  require Logger

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
        contents =
          """
          defmodule #{inspect(module_name)} do
            #{contents}
          end
          """

        location =
          case Keyword.get(opts, :path, nil) do
            nil ->
              proper_location(module_name)

            path ->
              path
          end

        Igniter.create_new_elixir_file(igniter, location, contents)
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

  @doc "Checks if a module is defined somewhere in the project. The returned igniter should not be discarded."
  def module_exists?(igniter, module_name) do
    case find_module(igniter, module_name) do
      {:ok, {igniter, _, _}} -> {true, igniter}
      {:error, igniter} -> {false, igniter}
    end
  end

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

  @doc """
  Finds a module, returning a new igniter, and the source and zipper location. This new igniter should not be discarded.

  In general, you should not use the returned source and zipper to update the module, instead, use this to interrogate
  the contents or source in some way, and then call `find_and_update_module/3` with a function to perform an update.
  """
  @spec find_module(Igniter.t(), module()) ::
          {:ok, {Igniter.t(), Rewrite.Source.t(), Zipper.t()}} | {:error, Igniter.t()}
  def find_module(igniter, module_name) do
    igniter = Igniter.include_all_elixir_files(igniter)

    igniter
    |> Map.get(:rewrite)
    |> Task.async_stream(fn source ->
      {source
       |> Rewrite.Source.get(:quoted)
       |> Zipper.zip()
       |> move_to_defmodule(module_name), source}
    end)
    |> Enum.find_value({:error, igniter}, fn
      {:ok, {{:ok, zipper}, source}} ->
        {:ok, {igniter, source, zipper}}

      _other ->
        false
    end)
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
      |> Task.async_stream(fn source ->
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
                |> Igniter.Code.Module.to_module_name()

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
      end)
      |> Enum.flat_map(fn {:ok, v} ->
        v
      end)

    {igniter, matching_modules}
  end

  @doc "Given a suffix, returns a module name with the prefix of the current project."
  @spec module_name(String.t()) :: module()
  def module_name(suffix) do
    Module.concat(module_name_prefix(), suffix)
  end

  @doc """
  Returns the idiomatic file location for a given module, starting with "lib/".

  Examples:

    iex> Igniter.Code.Module.proper_location(MyApp.Hello)
    "lib/my_app/hello.ex"
  """
  @spec proper_location(module(), source_folder :: String.t()) :: Path.t()
  def proper_location(module_name, source_folder \\ "lib") do
    do_proper_location(module_name, {:source_folder, source_folder})
  end

  @doc """
  Returns the test file location for a given module, according to
  `mix test` expectations, starting with "test/" and ending with "_test.exs".

  Examples:

    iex> Igniter.Code.Module.proper_test_location(MyApp.Hello)
    "test/my_app/hello_test.exs"

    iex> Igniter.Code.Module.proper_test_location(MyApp.HelloTest)
    "test/my_app/hello_test.exs"
  """
  @spec proper_test_location(module()) :: Path.t()
  def proper_test_location(module_name) do
    do_proper_location(module_name, :test)
  end

  @doc """
  Returns the test support location for a given module, starting with
  "test/support/" and dropping the module name prefix in the path.

  Examples:

    iex> Igniter.Code.Module.proper_test_support_location(MyApp.DataCase)
    "test/support/data_case.ex"
  """
  @spec proper_test_support_location(module()) :: Path.t()
  def proper_test_support_location(module_name) do
    do_proper_location(module_name, {:source_folder, "test/support"})
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
          {:ok, proper_test_location(module)}
        else
          :error
        end

      source_folder ->
        {:ok, proper_location(module, source_folder)}
    end
    |> case do
      :error ->
        nil

      {:ok, proper_location} ->
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
                File.dir?(inside_matching_folder_dirname) || just_created_folder?
              else
                source.path == proper_location(module) &&
                  !File.dir?(inside_matching_folder_dirname) && just_created_folder?
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

  @doc false
  def to_module_name({:__aliases__, _, parts}), do: Module.concat(parts)
  def to_module_name(value) when is_atom(value) and not is_nil(value), do: value
  def to_module_name(_), do: nil

  defp do_proper_location(module_name, kind) do
    path =
      module_name
      |> Module.split()
      |> Enum.map(&to_string/1)
      |> Enum.map(&Macro.underscore/1)

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

  def module?(zipper) do
    Common.node_matches_pattern?(zipper, {:__aliases__, _, [_ | _]})
  end

  @doc "Parses a string into a module name"
  @spec parse(String.t()) :: module()
  def parse(module_name) do
    module_name
    |> String.split(".")
    |> Module.concat()
  end

  @doc "The module name prefix based on the mix project's module name"
  @spec module_name_prefix() :: module()
  def module_name_prefix do
    Mix.Project.get!()
    |> Module.split()
    |> :lists.droplast()
    |> Module.concat()
  end

  @doc "Moves the zipper to a defmodule call"
  @spec move_to_defmodule(Zipper.t()) :: {:ok, Zipper.t()} | :error
  def move_to_defmodule(zipper) do
    Igniter.Code.Function.move_to_function_call_in_current_scope(zipper, :defmodule, 2)
  end

  @doc "Moves the zipper to a specific defmodule call"
  @spec move_to_defmodule(Zipper.t(), module()) :: {:ok, Zipper.t()} | :error
  def move_to_defmodule(zipper, module) do
    Igniter.Code.Function.move_to_function_call(
      zipper,
      :defmodule,
      2,
      fn zipper ->
        case Igniter.Code.Function.move_to_nth_argument(zipper, 0) do
          {:ok, zipper} ->
            Igniter.Code.Common.nodes_equal?(zipper, module)

          _ ->
            false
        end
      end
    )
  end

  @doc "Moves the zipper to the body of a module that `use`s the provided module (or one of the provided modules)."
  @spec move_to_module_using(Zipper.t(), module | list(module)) :: {:ok, Zipper.t()} | :error
  def move_to_module_using(zipper, [module]) do
    move_to_module_using(zipper, module)
  end

  def move_to_module_using(zipper, [module | rest] = one_of_modules)
      when is_list(one_of_modules) do
    case move_to_module_using(zipper, module) do
      {:ok, zipper} ->
        {:ok, zipper}

      :error ->
        move_to_module_using(zipper, rest)
    end
  end

  def move_to_module_using(zipper, module) do
    with {:ok, mod_zipper} <- move_to_defmodule(zipper),
         {:ok, mod_zipper} <- Igniter.Code.Common.move_to_do_block(mod_zipper),
         {:ok, _} <- move_to_use(mod_zipper, module) do
      {:ok, mod_zipper}
    else
      _ ->
        :error
    end
  end

  @deprecated "Use `move_to_use/2` instead."
  def move_to_using(zipper, module), do: move_to_use(zipper, module)

  @doc "Moves the zipper to the `use` statement for a provided module."
  def move_to_use(zipper, [module]), do: move_to_use(zipper, module)

  def move_to_use(zipper, [module | rest]) do
    case move_to_use(zipper, module) do
      {:ok, zipper} -> {:ok, zipper}
      _ -> move_to_use(zipper, rest)
    end
  end

  def move_to_use(zipper, module) do
    Igniter.Code.Function.move_to_function_call_in_current_scope(zipper, :use, [1, 2], fn call ->
      Igniter.Code.Function.argument_matches_predicate?(
        call,
        0,
        &Igniter.Code.Common.nodes_equal?(&1, module)
      )
    end)
  end

  @deprecated "Use `Igniter.Code.Function.move_to_defp/3` instead"
  def move_to_defp(zipper, fun, arity) do
    Igniter.Code.Function.move_to_defp(zipper, fun, arity)
  end

  @deprecated "Use `Igniter.Code.Function.move_to_def/3` instead"
  def move_to_def(zipper, fun, arity) do
    Igniter.Code.Function.move_to_def(zipper, fun, arity)
  end
end
