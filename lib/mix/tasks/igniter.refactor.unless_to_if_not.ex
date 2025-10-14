# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.Igniter.Refactor.UnlessToIfNot do
  use Igniter.Mix.Task

  @example "mix igniter.refactor.unless_to_if_not"

  @shortdoc "Rewrites occurrences of `unless x` to `if !x` across the project."
  @moduledoc """
  #{@shortdoc}

  ## Example

  ```bash
  #{@example}
  ```
  """

  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :igniter,
      example: @example
    }
  end

  def igniter(igniter) do
    Igniter.Refactors.Elixir.unless_to_if_not(igniter)
  end
end
