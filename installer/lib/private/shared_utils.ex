defmodule Installer.Lib.Private.SharedUtils do
  @moduledoc false
  @doc false
  def extract_positional_args(argv, argv \\ [], positional \\ [])
  def extract_positional_args([], argv, positional), do: {argv, positional}

  def extract_positional_args(argv, got_argv, positional) do
    case OptionParser.next(argv, switches: []) do
      {:ok, _key, _value, rest} ->
        extract_positional_args(
          rest,
          got_argv ++ [Enum.at(argv, 0), Enum.at(argv, 1)],
          positional
        )

      {:invalid, _key, _value, rest} ->
        extract_positional_args(
          rest,
          got_argv ++ [Enum.at(argv, 0), Enum.at(argv, 1)],
          positional
        )

      {:undefined, _key, _value, rest} ->
        extract_positional_args(
          rest,
          got_argv ++ [Enum.at(argv, 0), Enum.at(argv, 1)],
          positional
        )

      {:error, rest} ->
        [first | rest] = rest
        extract_positional_args(rest, got_argv, positional ++ [first])
    end
  end
end
