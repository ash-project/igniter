# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.Igniter.Remove do
  use Igniter.Mix.Task

  @example "mix igniter.remove dep1 dep2"

  @shortdoc "Removes the provided deps from `mix.exs`"
  @moduledoc """
  #{@shortdoc}

  This task also unlocks and cleans any unused dependencies after completion.

  ## Important Note

  Igniter does not have a concept of "uninstallers" right now. All that this task does
  is remove dependencies. If you still have usages of a given dependency, then you will
  have to clean that up yourself (and likely want to do it before removing
  the dependency).

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
      Igniter.Project.Deps.remove_dep(igniter, name)
    end)
    |> Igniter.add_task("deps.clean", ["--unlock", "--unused"])
  end
end
