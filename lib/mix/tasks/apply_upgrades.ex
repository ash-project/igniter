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
    packages = igniter.args.positional.packages

    Enum.reduce(packages, igniter, fn package, igniter ->
      case String.split(package, ":", parts: 3, trim: true) do
        [name, from, to] ->
          task_name =
            if name == "igniter" do
              "igniter.upgrade_igniter"
            else
              "#{name}.upgrade"
            end

          Igniter.compose_task(igniter, task_name, [from, to] ++ igniter.args.argv_flags)

        _ ->
          Mix.raise("Invalid package format: #{package}")
      end
    end)
  end
end
