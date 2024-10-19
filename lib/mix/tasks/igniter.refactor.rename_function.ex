defmodule Mix.Tasks.Igniter.Refactor.RenameFunction do
  use Igniter.Mix.Task

  @example "mix igniter.refactor.rename_function Mod.fun NewMod.new_fun"

  @shortdoc "A short description of your task"
  @moduledoc """
  #{@shortdoc}

  Rename a given function across a whole project.
  This will remap definitions in addition to calls and references.

  Keep in mind that it cannot detect 100% of cases, and will always
  miss usage of `apply/3` for dynamic function calling.

  If the new module is different than the old module, the function will be moved.
  If the new module does not exist, it will be created.

  Pass an arity to the first function to only rename a specific arity definition.

  ## Options

  - `--deprecate` - `soft | hard` The old function will remain in place but deprecated. Soft deprecations,
    only affect documentation, while hard deprecations will display a warning when the function is called.

  ## Example

  ```bash
  #{@example}
  ```
  """

  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :igniter,
      example: @example,
      positional: [:old, :new],
      schema: [
        deprecate: :string
      ]
    }
  end

  def igniter(igniter, argv) do
    # extract positional arguments according to `positional` above
    {arguments, argv} = positional_args!(argv)
    options = options!(argv)

    deprecate =
      case options[:deprecate] do
        nil ->
          nil

        "hard" ->
          :hard

        "soft" ->
          :soft

        other ->
          Mix.shell().error("Invalid deprecation type: #{other}")
          exit({:shutdown, 1})
      end

    {old_mod, old_fun, old_arity} = parse_fun(arguments[:old])
    {new_mod, new_fun, new_arity} = parse_fun(arguments[:new])

    arity =
      cond do
        is_integer(old_arity) and new_arity == :any ->
          old_arity

        old_arity != new_arity ->
          Mix.shell().error(
            "Arity must be the same between old and new function (or omitted for the new function)"
          )

          exit({:shutdown, 1})

        true ->
          old_arity
      end

    Igniter.Refactors.Rename.rename_function(
      igniter,
      {old_mod, old_fun},
      {new_mod, new_fun},
      arity: arity,
      deprecate: deprecate
    )
  end

  def parse_fun(input) do
    with parts <- String.split(input, ".", trim: true),
         fun <- List.last(parts),
         parts <- :lists.droplast(parts),
         mod <- Enum.join(parts, "."),
         {fun, arity} <- fun_to_arity(fun),
         fun <- String.to_atom(fun),
         mod <- Igniter.Project.Module.parse(mod) do
      {mod, fun, arity}
    else
      _ ->
        Mix.shell().error("Invalid function format: #{input}")
        exit({:shutdown, 1})
    end
  end

  defp fun_to_arity(fun) do
    case String.split(fun, "/", parts: 2, trim: true) do
      [fun] ->
        {fun, :any}

      [fun, arity] ->
        case Integer.parse(arity) do
          {arity, ""} ->
            {fun, arity}

          _ ->
            :error
        end

      _ ->
        :error
    end
  end
end
