defmodule Igniter.Code.Module do
  @moduledoc "Utilities for working with Elixir modules"
  require Igniter.Code.Common
  alias Igniter.Code.Common
  alias Sourceror.Zipper

  @doc "Finds a module and updates its contents wherever it is. If it does not exist, it is created with the provided contents."
  def find_and_update_or_create_module(igniter, module_name, contents, updater, path \\ nil) do
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

        Igniter.create_new_elixir_file(igniter, path || proper_location(module_name), contents)
    end
  end

  @doc "Checks if a module is defined somewhere in the project. The returned igniter should not be discarded."
  def module_exists?(igniter, module_name) do
    case find_and_update_module(igniter, module_name, &{:ok, &1}) do
      {:ok, igniter} -> {true, igniter}
      _ -> {false, igniter}
    end
  end

  @doc "Finds a module and updates its contents. Returns `{:error, igniter}` if the module could not be found. Do not discard this igniter."
  @spec find_and_update_module(Igniter.t(), module(), (Zipper.t() -> {:ok, Zipper.t()} | :error)) ::
          {:ok, Igniter.t()} | {:error, Igniter.t()}
  def find_and_update_module(igniter, module_name, updater) do
    case find_module(igniter, module_name) do
      {igniter, source, zipper} ->
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

      nil ->
        {:error, igniter}
    end
  end

  @doc """
  Finds a module, returning a new igniter, and the source and zipper location. This new igniter should not be discarded.

  In general, you should not use the returned source and zipper to update the module, instead, use this to interrogate
  the contents or source in some way, and then call `find_and_update_module/3` with a function to perform an update.
  """
  @spec find_module(Igniter.t(), module()) :: {Igniter.t(), Rewrite.Source.t(), Zipper.t()} | nil
  def find_module(igniter, module_name) do
    igniter = Igniter.include_all_elixir_files(igniter)

    igniter
    |> Map.get(:rewrite)
    |> Enum.find_value(fn source ->
      source
      |> Rewrite.Source.get(:quoted)
      |> Zipper.zip()
      |> Igniter.Code.Common.move_to_zipper(fn zipper ->
        with true <- Igniter.Code.Function.function_call?(zipper, :defmodule, 2),
             {:ok, inner_zipper} <- Igniter.Code.Function.move_to_nth_argument(zipper, 0),
             inner_zipper <- Igniter.Code.Common.expand_aliases(inner_zipper),
             true <-
               Igniter.Code.Common.nodes_equal?(
                 inner_zipper,
                 module_name
               ) do
          {:ok, inner_zipper}
        else
          _ ->
            nil
        end
      end)
      |> case do
        {:ok, zipper} ->
          {igniter, source, zipper}

        _ ->
          nil
      end
    end)
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
  @spec proper_location(module()) :: Path.t()
  def proper_location(module_name) do
    do_proper_location(module_name, :lib)
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
    do_proper_location(module_name, :test_support)
  end

  @doc false
  def move_files(igniter, opts \\ []) do
    module_location_config = Igniter.Project.IgniterConfig.get(igniter, :module_location)
    igniter = Igniter.include_all_elixir_files(igniter)

    igniter.rewrite
    |> Enum.filter(&(Path.extname(&1.path) == ".ex"))
    |> Enum.reduce(igniter, fn source, igniter ->
      zipper =
        source
        |> Rewrite.Source.get(:quoted)
        |> Zipper.zip()

      with {:ok, zipper} <- Igniter.Code.Module.move_to_defmodule(zipper),
           {:defmodule, _, [module | _]} <-
             zipper
             |> Igniter.Code.Common.expand_aliases()
             |> Zipper.subtree()
             |> Zipper.node(),
           module when not is_nil(module) <- to_module_name(module),
           new_path when not is_nil(new_path) <-
             should_move_file_to(igniter.rewrite, source, module, module_location_config, opts) do
        Igniter.move_file(igniter, source.path, new_path, error_if_exists?: false)
      else
        _ ->
          igniter
      end
    end)
  end

  defp should_move_file_to(rewrite, source, module, module_location_config, opts) do
    all_paths = Rewrite.paths(rewrite)

    paths_created =
      rewrite
      |> Enum.filter(fn source ->
        Rewrite.Source.from?(source, :string)
      end)
      |> Enum.map(& &1.path)

    last = source.path |> Path.split() |> List.last() |> Path.rootname()

    path_it_might_live_in =
      case module_location_config do
        :inside_matching_folder ->
          source.path
          |> Path.split()
          |> Enum.reverse()
          |> Enum.drop(1)
          |> Enum.reverse()
          |> Enum.concat([last])

        :outside_matching_folder ->
          module
          |> proper_location()
          |> Path.split()
          |> Enum.reverse()
          |> Enum.drop(1)
          |> Enum.reverse()
      end

    if Rewrite.Source.from?(source, :string) do
      if opts[:move_all?] ||
           (module_location_config == :inside_matching_folder &&
              Enum.any?(all_paths, fn path ->
                List.starts_with?(Path.split(path), path_it_might_live_in)
              end)) do
        path_it_might_live_in
      end
    else
      # only move a file if we just created its new home, or if `move_all?` is set
      if opts[:move_all?] ||
           (!File.dir?(Path.join(path_it_might_live_in)) &&
              module_location_config == :inside_matching_folder &&
              Enum.any?(paths_created, fn path ->
                List.starts_with?(Path.split(path), path_it_might_live_in)
              end)) do
        path_it_might_live_in
      end
    end
    |> if do
      Path.join(path_it_might_live_in ++ [last <> ".ex"])
    else
      nil
    end
  end

  defp to_module_name({:__aliases__, _, parts}), do: Module.concat(parts)
  defp to_module_name(value) when is_atom(value) and not is_nil(value), do: value
  defp to_module_name(_), do: nil

  defp do_proper_location(module_name, kind) do
    path =
      module_name
      |> Module.split()
      |> Enum.map(&to_string/1)
      |> Enum.map(&Macro.underscore/1)

    last = List.last(path)
    leading = :lists.droplast(path)

    case kind do
      :lib ->
        Path.join(["lib" | leading] ++ ["#{last}.ex"])

      :test ->
        if String.ends_with?(last, "_test") do
          Path.join(["test" | leading] ++ ["#{last}.exs"])
        else
          Path.join(["test" | leading] ++ ["#{last}_test.exs"])
        end

      :test_support ->
        [_prefix | leading_rest] = leading
        Path.join(["test/support" | leading_rest] ++ ["#{last}.ex"])
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

  # sobelow_skip ["DOS.StringToAtom"]
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

  # sobelow_skip ["DOS.StringToAtom"]
  def move_to_module_using(zipper, module) do
    split_module =
      module
      |> Module.split()
      |> Enum.map(&String.to_atom/1)

    with {:ok, zipper} <- Common.move_to_pattern(zipper, {:defmodule, _, [_, _]}),
         subtree <- Zipper.subtree(zipper),
         subtree <- subtree |> Zipper.down() |> Zipper.rightmost(),
         subtree <- remove_module_definitions(subtree),
         {:ok, _found} <-
           Common.move_to(subtree, fn
             {:use, _, [^module | _]} ->
               true

             {:use, _, [{:__aliases__, _, ^split_module} | _]} ->
               true
           end) do
      Common.move_to_do_block(zipper)
    else
      _ ->
        :error
    end
  end

  @doc "Moves the zipper to the `use` statement for a provided module."
  def move_to_use(zipper, module) do
    Igniter.Code.Function.move_to_function_call_in_current_scope(zipper, :use, [1, 2], fn call ->
      Igniter.Code.Function.argument_matches_predicate?(
        call,
        0,
        &Igniter.Code.Common.nodes_equal?(&1, module)
      )
    end)
  end

  def move_to_defp(zipper, fun, arity) do
    do_move_to_def(zipper, fun, arity, :defp)
  end

  def move_to_def(zipper, fun, arity) do
    do_move_to_def(zipper, fun, arity, :def)
  end

  defp do_move_to_def(zipper, fun, arity, kind) do
    case Common.move_to_pattern(
           zipper,
           {^kind, _, [{^fun, _, args}, _]} when length(args) == arity
         ) do
      :error ->
        if arity == 0 do
          case Common.move_to_pattern(
                 zipper,
                 {^kind, _, [{^fun, _, context}, _]} when is_atom(context)
               ) do
            :error ->
              :error

            {:ok, zipper} ->
              Common.move_to_do_block(zipper)
          end
        else
          :error
        end

      {:ok, zipper} ->
        Common.move_to_do_block(zipper)
    end
  end

  defp remove_module_definitions(zipper) do
    Zipper.traverse(zipper, fn
      {:defmodule, _, _} ->
        Zipper.remove(zipper)

      other ->
        other
    end)
  end
end
