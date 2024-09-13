defmodule Mix.Tasks.Igniter.MoveFiles do
  @moduledoc "Moves any relavant files to their 'correct' location."
  @shortdoc @moduledoc
  use Igniter.Mix.Task

  def igniter(igniter, _argv) do
    Mix.shell().info("Finding all modules and determining proper locations...")
    Igniter.Project.Module.move_files(igniter, move_all?: true)
  end
end
