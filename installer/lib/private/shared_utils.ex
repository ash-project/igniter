defmodule Installer.Lib.Private.SharedUtils do
  @moduledoc false
  @doc false
  def extract_positional_args(argv, argv \\ [], positional \\ [])
  def extract_positional_args([], argv, positional), do: {argv, positional}

  def extract_positional_args(argv, got_argv, positional) do
    case OptionParser.next(argv, switches: []) do
      {_, _key, true, rest} ->
        extract_positional_args(
          rest,
          got_argv ++ [Enum.at(argv, 0)],
          positional
        )

      {_, _key, _value, rest} ->
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

  def reevaluate_mix_exs() do
    old_undefined = Code.get_compiler_option(:no_warn_undefined)
    old_relative_paths = Code.get_compiler_option(:relative_paths)
    old_ignore_module_conflict = Code.get_compiler_option(:ignore_module_conflict)

    try do
      Code.compiler_options(
        relative_paths: false,
        no_warn_undefined: :all,
        ignore_module_conflict: true
      )

      _ = Code.compile_file("mix.exs")
    after
      Code.compiler_options(
        relative_paths: old_relative_paths,
        no_warn_undefined: old_undefined,
        ignore_module_conflict: old_ignore_module_conflict
      )
    end
  end
end
