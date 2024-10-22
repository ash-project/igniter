defmodule Mix.Tasks.Igniter.Install do
  @moduledoc Installer.Lib.Private.SharedUtils.igniter_install_docs()
  use Mix.Task

  @requirements "deps.compile"

  @impl true
  @shortdoc "Install a package or packages, and run any associated installers."
  def run(argv) do
    Mix.Task.run("compile", ["--no-compile"])

    {argv, positional} = Installer.Lib.Private.SharedUtils.extract_positional_args(argv)

    packages =
      positional
      |> Enum.join(",")
      |> String.split(",", trim: true)

    if Enum.empty?(packages) do
      raise ArgumentError, "must provide at least one package to install"
    end

    Application.ensure_all_started(:rewrite)

    Igniter.Util.Install.install(Enum.join(packages, ","), argv)
  end
end
