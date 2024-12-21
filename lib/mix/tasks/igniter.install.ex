defmodule Mix.Tasks.Igniter.Install do
  @moduledoc Installer.Lib.Private.SharedUtils.igniter_install_docs()
  use Mix.Task

  @requirements "deps.compile"

  @impl true
  @shortdoc "Install a package or packages, and run any associated installers."
  def run(argv) do
    Installer.Lib.Private.SharedUtils.install(argv)
  end
end
