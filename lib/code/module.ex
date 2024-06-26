defmodule Igniter.Code.Module do
  @moduledoc "Utilities for working with Elixir modules"
  require Igniter.Code.Common
  alias Igniter.Code.Common
  alias Sourceror.Zipper

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
    do_proper_test_location(module_name, :lib)
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
    do_proper_test_location(module_name, :test)
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
    do_proper_test_location(module_name, :test_support)
  end

  defp do_proper_test_location(module_name, kind) do
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
