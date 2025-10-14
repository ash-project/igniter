# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule Igniter.Mix.Task.Args do
  @moduledoc """
  Command line arguments parsed when running an `Igniter.Mix.Task`.

  These args will usually be accessed through `igniter.args` when the
  `c:Igniter.Mix.Task.igniter/1` callback is run. To learn more about how
  they are parsed, see `Igniter.Mix.Task.Info`.
  """

  defstruct positional: %{}, options: [], argv_flags: [], argv: []

  @type t :: %__MODULE__{
          positional: %{atom() => term()},
          options: keyword(),
          argv_flags: list(String.t()),
          argv: list(String.t())
        }
end
