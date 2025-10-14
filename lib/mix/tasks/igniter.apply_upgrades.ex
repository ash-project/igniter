# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.Igniter.ApplyUpgrades do
  use Igniter.Mix.Task

  @example "mix igniter.apply_upgrades package1:0.3.1:0.3.2 package2:1.2.4:1.5.9"

  @shortdoc "Applies the upgrade scripts for the list of package version changes provided."
  @moduledoc """
  #{@shortdoc}

  This can be used to explicitly run specific upgrade scripts within a given version range for a package.
  This is also *required* if your call to `mix igniter.upgrade` requires an upgrade of igniter itself.

  ```bash
  #{@example}
  ```

  ## Options

  * `--yes` or `-y` - Accept all changes automatically
  """

  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :igniter,
      example: @example,
      positional: [
        packages: [rest: true]
      ],
      schema: [
        yes: :boolean
      ],
      aliases: [y: :yes],
      defaults: [yes: false]
    }
  end

  def igniter(igniter) do
    Igniter.CopiedTasks.do_apply_upgrades(igniter)
  end
end
