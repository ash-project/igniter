defmodule Mix.Tasks.Igniter.Install do
  @moduledoc """
  Install a package or packages, and run any associated installers.

  ## Args

  mix igniter.install package1,package2,package3

  ## Switches

  * `--dry-run` - `d` - Run the task without making any changes.
  * `--yes` - `y` - Automatically answer yes to any prompts.
  * `--example` - `e` - Request that installed packages include initial example code.
  """
  use Mix.Task

  @impl true
  @shortdoc "Install a package or packages, and run any associated installers."
  def run([install | argv]) do
    Application.ensure_all_started([:rewrite])

    Igniter.Install.install(install, argv)
  end

  def run([]) do
    raise "must provide a package to install!"
  end
end
