defmodule Mix.Tasks.Igniter.Setup do
  @moduledoc "Creates or updates a .igniter.exs file, used to configure Igniter for end user's preferences."

  @shortdoc @moduledoc
  use Igniter.Mix.Task

  def igniter(igniter, _argv) do
    Igniter.Project.IgniterConfig.setup(igniter)
  end
end
