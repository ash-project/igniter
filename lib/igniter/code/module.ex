defmodule Igniter.Code.Module do
  @moduledoc "Utilities for working with Elixir modules"
  require Igniter.Code.Common
  alias Igniter.Code.Common
  alias Sourceror.Zipper

  require Logger

  @doc "The module name prefix based on the mix project's module name"
  @deprecated "Use `Igniter.Project.Module.module_name_prefix/1` instead"
  @spec module_name_prefix() :: module()
  def module_name_prefix do
    Mix.Project.get!()
    |> Module.split()
    |> :lists.droplast()
    |> Module.concat()
  end

  @doc "The module name prefix based on the mix project's module name"
  @spec module_name_prefix(Igniter.t()) :: module()
  @deprecated "Use `Igniter.Project.Module.module_name_prefix/1` instead"
  def module_name_prefix(igniter) do
    Igniter.Project.Module.module_name_prefix(igniter)
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

  def module?(zipper) do
    Common.node_matches_pattern?(zipper, {:__aliases__, _, [_ | _]})
  end

  @doc """
  Finds a module and updates its contents wherever it is.

  If the module does not yet exist, it is created with the provided contents. In that case,
  the path is determined with `Igniter.Code.Module.proper_location/2`, but may optionally be overwritten with options below.

  # Options

  - `:path` - Path where to create the module, relative to the project root. Default: `nil` (uses `:kind` to determine the path).
  """
  @deprecated "Use `Igniter.Project.Module.find_and_update_or_create_module/5` instead"
  def find_and_update_or_create_module(igniter, module_name, contents, updater, opts \\ []) do
    Igniter.Project.Module.find_and_update_or_create_module(
      igniter,
      module_name,
      contents,
      updater,
      opts
    )
  end

  @doc "Checks if the value is a module that matches a given predicate"
  def module_matching?(zipper, pred) do
    zipper =
      zipper
      |> Igniter.Code.Common.maybe_move_to_single_child_block()
      |> Igniter.Code.Common.expand_aliases()

    case zipper.node do
      {:__aliases__, _, parts} ->
        pred.(Module.concat(parts))

      value when is_atom(value) ->
        pred.(value)

      _ ->
        false
    end
  end

  @doc "Creates a new file & module in its appropriate location."
  @deprecated "Use `Igniter.Project.Module.create_module/4` instead"
  def create_module(igniter, module_name, contents, opts \\ []) do
    Igniter.Project.Module.create_module(igniter, module_name, contents, opts)
  end

  @doc "Checks if a module is defined somewhere in the project. The returned igniter should not be discarded."
  @deprecated "Use `Igniter.Project.Module.module_exists/2` instead"
  def module_exists?(igniter, module_name) do
    Igniter.Project.Module.module_exists(igniter, module_name)
  end

  @deprecated "Use `Igniter.Project.Module.find_and_update_module!/3` instead"
  def find_and_update_module!(igniter, module_name, updater) do
    Igniter.Project.Module.find_and_update_module!(igniter, module_name, updater)
  end

  @doc "Finds a module and updates its contents. Returns `{:error, igniter}` if the module could not be found. Do not discard this igniter."
  @spec find_and_update_module(Igniter.t(), module(), (Zipper.t() -> {:ok, Zipper.t()} | :error)) ::
          {:ok, Igniter.t()} | {:error, Igniter.t()}
  @deprecated "Use `Igniter.Project.Module.find_and_update_module/3` instead"
  def find_and_update_module(igniter, module_name, updater) do
    Igniter.Project.Module.find_and_update_module(igniter, module_name, updater)
  end

  @doc """
  Finds a module, returning a new igniter, and the source and zipper location. This new igniter should not be discarded.

  In general, you should not use the returned source and zipper to update the module, instead, use this to interrogate
  the contents or source in some way, and then call `find_and_update_module/3` with a function to perform an update.
  """
  @spec find_module(Igniter.t(), module()) ::
          {:ok, {Igniter.t(), Rewrite.Source.t(), Zipper.t()}} | {:error, Igniter.t()}
  @deprecated "Use `Igniter.Project.Module.find_module/2` instead"
  def find_module(igniter, module_name) do
    Igniter.Project.Module.find_module(igniter, module_name)
  end

  @doc """
  Finds a module, raising an error if its not found.

  See `find_module/2` for more information.
  """
  @spec find_module!(Igniter.t(), module()) ::
          {Igniter.t(), Rewrite.Source.t(), Zipper.t()} | no_return
  @deprecated "Use `Igniter.Project.Module.find_module!/2` instead"
  def find_module!(igniter, module_name) do
    Igniter.Project.Module.find_module!(igniter, module_name)
  end

  @spec find_all_matching_modules(igniter :: Igniter.t(), (module(), Zipper.t() -> boolean)) ::
          {Igniter.t(), [module()]}
  @deprecated "Use `Igniter.Project.Module.find_all_matching_modules/2` instead"
  def find_all_matching_modules(igniter, predicate) do
    Igniter.Project.Module.find_all_matching_modules(igniter, predicate)
  end

  @doc "Given a suffix, returns a module name with the prefix of the current project."
  @spec module_name(String.t()) :: module()
  @deprecated "Use `module_name/2` instead."
  def module_name(suffix) do
    Module.concat(module_name_prefix(), suffix)
  end

  @doc "Given a suffix, returns a module name with the prefix of the current project."
  @spec module_name(Igniter.t(), String.t()) :: module()
  @deprecated "Use `Igniter.Project.Module.module_name/2` instead."
  def module_name(igniter, suffix) do
    Igniter.Project.Module.module_name(igniter, suffix)
  end

  @doc "Parses a string into a module name"
  @deprecated "Use `Igniter.Project.Module.parse/1` instead."
  @spec parse(String.t()) :: module()
  def parse(module_name) do
    Igniter.Project.Module.parse(module_name)
  end

  @doc """
  Returns the idiomatic file location for a given module, starting with "lib/".
  """
  @spec proper_location(module(), source_folder :: String.t()) :: Path.t()
  @deprecated "Use `Igniter.Project.Module.proper_location/3`"
  def proper_location(module_name, source_folder \\ "lib") do
    Igniter.Project.Module.proper_location(
      Igniter.new(),
      module_name,
      {:source_folder, source_folder}
    )
  end

  @doc """
  Returns the test file location for a given module, according to
  `mix test` expectations, starting with "test/" and ending with "_test.exs".

  """
  @spec proper_test_location(module()) :: Path.t()
  @deprecated "Use `Igniter.Project.Module.proper_location/3`"
  def proper_test_location(module_name) do
    Igniter.Project.Module.proper_location(Igniter.new(), module_name, :test)
  end

  @doc """
  Returns the test support location for a given module, starting with
  "test/support/" and dropping the module name prefix in the path.
  """
  @spec proper_test_support_location(module()) :: Path.t()
  @deprecated "Use `Igniter.Project.Module.proper_location/3`"
  def proper_test_support_location(module_name) do
    Igniter.Project.Module.proper_location(
      Igniter.new(),
      module_name,
      {:source_folder, "test/support"}
    )
  end
end
