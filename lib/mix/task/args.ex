defmodule Igniter.Mix.Task.Args do
  @moduledoc """
  Command line arguments parsed when running an `Igniter.Mix.Task`.
  """

  defstruct positional: %{}, options: [], argv_flags: [], argv: []

  @type t :: %__MODULE__{
          positional: %{atom() => term()},
          options: keyword(),
          argv_flags: list(String.t()),
          argv: list(String.t())
        }
end
