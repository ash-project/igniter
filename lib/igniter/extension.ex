defmodule Igniter.Extension do
  @moduledoc """
  Alter igniter's behavior by adding new functionality.

  This is used to allow frameworks to modify things like
  the conventional location of files.
  """

  defmacro __using__(_) do
    quote do
      @behaviour Igniter.Extension
    end
  end

  @doc """
  Choose a proper location for any given module.

  Possible return values:

  - `{:ok, path}`: The path where the module should be located.
  - `:error`: It should go in the default place, or according to other extensions.
  - `:keep`: Keep the module in the same location, unless another extension has a place for it, or its just been created.
  """
  @callback proper_location(
              Igniter.t(),
              module(),
              Keyword.t()
            ) :: {:ok, Path.t()} | :error
end
