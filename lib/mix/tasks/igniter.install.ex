defmodule Mix.Tasks.Igniter.Install do
  use Mix.Task

  @impl true
  def run([install | argv]) do
    Application.ensure_all_started([:rewrite])

    Igniter.Install.install(install, argv)
  end

  def run([]) do
    raise "must provide a package to install!"
  end
end
