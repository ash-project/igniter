defmodule Mix.Tasks.Igniter.Install do
  @moduledoc Installer.Lib.Private.SharedUtils.igniter_install_docs()
  use Mix.Task

  @impl true
  @shortdoc "Install a package or packages, and run any associated installers."
  def run(argv) do
    Mix.Task.run("deps.compile")
    Mix.Task.run("deps.loadpaths")
    Installer.Lib.Private.SharedUtils.install(argv)
  end
end
