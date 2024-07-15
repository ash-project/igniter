defmodule Igniter.Util.Warning do
  @moduledoc "Utilities for emitting well formatted warnings"
  def warn_with_code_sample(igniter, message, code) do
    Igniter.add_warning(igniter, formatted_warning(message, code))
  end

  def formatted_warning(message, code) do
    formatted =
      Code.format_string!(code)
      |> IO.iodata_to_binary()
      |> String.split("\n")
      |> Enum.map_join("\n", &("  " <> &1))

    """
    #{message}

    #{formatted}
    """
  end
end
