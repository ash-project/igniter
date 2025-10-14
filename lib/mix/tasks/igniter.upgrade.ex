# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.Igniter.Upgrade do
  use Igniter.Mix.Task

  @example "mix igniter.upgrade package1 package2@1.2.1"

  @shortdoc "Fetch and upgrade dependencies. A drop in replacement for `mix deps.update` that also runs upgrade tasks."
  @moduledoc """
  #{@shortdoc}

  Updates dependencies via `mix deps.update` and then runs any upgrade tasks for any changed dependencies.

  By default, this task updates to the latest versions allowed by the `mix.exs` file, just like `mix deps.update`.

  To upgrade a package to a specific version, you can specify the version after the package name,
  separated by an `@` symbol. This allows upgrading beyond what your mix.exs file currently specifies,
  i.e if you have `~> 1.0` in your mix.exs file, you can use `mix igniter.upgrade package@2.0` to
  upgrade to version 2.0, which will update your `mix.exs` and run any equivalent upgraders.

  ## Limitations

  The new version of the package must be "compile compatible" with your existing code. See the upgrades guide for more.

  ## Example

  ```bash
  #{@example}
  ```

  ## Options

  * `--yes` - Accept all changes automatically
  * `--all` - Upgrades all dependencies
  * `--only` - only fetches dependencies for given environment
  * `--verbose` - display additional output from various operations
  * `--target` - only fetches dependencies for given target
  * `--no-archives-check` - does not check archives before fetching deps
  * `--git-ci` - Uses git history (HEAD~1) to check the previous versions in the lock file.
    See the upgrade guides for more. Sets --yes automatically.
  """

  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :igniter,
      example: @example,
      positional: [
        packages: [rest: true, optional: true]
      ],
      schema: Igniter.CopiedTasks.upgrade_switches(),
      # if we add aliases, put them in upgrade switches
      aliases: [],
      defaults: [yes: false, yes_to_deps: false]
    }
  end

  def igniter(igniter) do
    Igniter.Upgrades.upgrade(igniter)
  end
end
