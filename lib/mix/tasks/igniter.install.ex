defmodule Mix.Tasks.Igniter.Install do
  use Mix.Task

  @impl true
  def run([install | argv]) do
    Application.ensure_all_started([:rewrite])

    if String.contains?(install, "/") do
      raise "installation from github not supported yet"
    else
      Mix.Task.run("igniter.install_from_hex", [install | argv])
    end
  end

  def run([]) do
    raise "must provide a package to install!"
  end
end
