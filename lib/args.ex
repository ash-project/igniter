defmodule Igniter.Args do
  @moduledoc "Tools for validating and parsing command line arguments to tasks."
  def validate_nth_present_and_underscored(igniter, argv, n, option, message) do
    value = Enum.at(argv, n)

    cond do
      !value ->
        {:error, Igniter.add_issue(igniter, message)}

      not (Macro.underscore(value) == value) ->
        {:error,
         Igniter.add_issue(
           igniter,
           "Must provide the #{option} in snake_case. Did you mean `#{Macro.underscore(value)}`"
         )}

      true ->
        {:ok, value}
    end
  end

  def validate_present_and_underscored(igniter, opts, option, message) do
    cond do
      !opts[option] ->
        {:error, Igniter.add_issue(igniter, message)}

      not (Macro.underscore(opts[option]) == opts[option]) ->
        {:error,
         Igniter.add_issue(
           igniter,
           "Must provide the #{option} in snake_case. Did you mean `#{Macro.underscore(opts[:option])}`"
         )}

      true ->
        {:ok, opts[option]}
    end
  end
end
