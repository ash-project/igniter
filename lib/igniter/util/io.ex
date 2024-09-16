defmodule Igniter.Util.IO do
  @moduledoc "Helpers for working with input/output"

  @doc "Prompts the user for yes or no, repeating the prompt until a satisfactory answer is given"
  def yes?(prompt) do
    case String.trim(Mix.shell().prompt(prompt <> " [Yn]")) do
      yes when yes in ["y", "Y", "yes", "YES"] ->
        true

      no when no in ["n", "N", "no", "NO"] ->
        false

      value ->
        Mix.shell().info("Please enter one of [Yn]. Got: #{value}")
        yes?(prompt)
    end
  end
end
