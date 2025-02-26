defmodule Mix.Tasks.Local.Igniter do
  use Mix.Task

  @shortdoc "Updates the Igniter project generator locally"

  @moduledoc """
  Updates the Igniter project generator locally.

      $ mix local.igniter

  Accepts the same command line options as `archive.install hex igniter_new`.
  """

  @impl true
  def run(args) do
    Mix.Task.run("archive.install", ["hex", "igniter_new" | args])
  end
end
