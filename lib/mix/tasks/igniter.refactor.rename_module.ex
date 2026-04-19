# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.Igniter.Refactor.RenameModule do
  use Igniter.Mix.Task

  @example "mix igniter.refactor.rename_module Foo.Bar Foo.Baz"

  @shortdoc "Rename a module across a project with automatic reference updates."
  @moduledoc """
  #{@shortdoc}

  Rename a given module across a whole project.

  Renames the module everywhere it appears: `defmodule`, `alias`, `use`,
  `import`, `require`, and all call sites. Also handles submodules, the
  corresponding test module, string literals mentioning the module name, and
  moves the file(s) to match the new module's proper location.

  Keep in mind that it cannot detect 100% of cases, and will always miss
  usage of dynamic module references (e.g. via `apply/3`).

  ## Example

  ```bash
  #{@example}
  ```
  """

  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :igniter,
      example: @example,
      positional: [:old_module, :new_module]
    }
  end

  def igniter(igniter) do
    arguments = igniter.args.positional

    old_module = Igniter.Project.Module.parse(arguments[:old_module])
    new_module = Igniter.Project.Module.parse(arguments[:new_module])

    Igniter.Refactors.Rename.rename_module(igniter, old_module, new_module)
  end
end
