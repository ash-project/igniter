# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.Igniter.MoveFiles do
  @moduledoc "Moves any relevant files to their 'correct' location."
  @shortdoc @moduledoc
  use Igniter.Mix.Task

  def igniter(igniter) do
    Mix.shell().info("Finding all modules and determining proper locations...")
    Igniter.Project.Module.move_files(igniter, move_all?: true)
  end
end
