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
    ignore_module_conflict = Code.get_compiler_option(:ignore_module_conflict)

    Code.put_compiler_option(:ignore_module_conflict, true)

    Mix.Task.run("archive.install", ["hex", "igniter_new" | args])

    Code.put_compiler_option(:ignore_module_conflict, ignore_module_conflict)
  end
end
