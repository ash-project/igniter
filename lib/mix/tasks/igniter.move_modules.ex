defmodule Mix.Tasks.Igniter.MoveModules do
  @moduledoc "Moves all modules to their 'correct' location."
  @shortdoc @moduledoc
  use Igniter.Mix.Task

  def igniter(igniter, _argv) do
    Igniter.Code.Module.move_modules(igniter, move_all?: true)
  end
end
