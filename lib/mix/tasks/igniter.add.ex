defmodule Mix.Tasks.Igniter.Add do
  use Igniter.Mix.Task

  @example "mix igniter.add dep1 dep2"

  @shortdoc "Adds the provided deps to `mix.exs`"
  @moduledoc """
  #{@shortdoc}

  This is only useful when you want to add a dependency without running its installer, since `igniter.install` already adds the dependency to `mix.exs`.

  This task also gets the dependencies after completion.

  ## Example

  ```bash
  #{@example}
  ```
  """

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      positional: [deps: [rest: true]]
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    igniter.args.positional.deps
    |> Enum.join(",")
    |> String.split(",")
    |> Enum.map(&String.to_atom/1)
    |> Enum.reduce(igniter, fn name, igniter ->
      Igniter.Project.Deps.add_dep(igniter, {name, ">= 0.0.0"})
    end)
    |> Igniter.add_task("deps.get")
  end
end
