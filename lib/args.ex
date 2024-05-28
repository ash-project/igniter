defmodule Igniter.Args do
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
