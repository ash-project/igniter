# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule Igniter.Util.IO do
  @moduledoc "Helpers for working with input/output"

  @doc "Prompts the user for yes or no, repeating the prompt until a satisfactory answer is given"
  def yes?(prompt) do
    case Mix.shell().prompt(prompt <> " [Y/n]") do
      :eof ->
        raise "No input detected when asking for confirmation, perhaps you meant to use `--yes`?"

      str ->
        case String.trim(str) do
          # default answer Y
          "" ->
            true

          yes when yes in ["y", "Y", "yes", "YES"] ->
            true

          no when no in ["n", "N", "no", "NO"] ->
            false

          value ->
            Mix.shell().info("Please enter one of [y/n]. Got: #{value}")
            yes?(prompt)
        end
    end
  end

  @doc """
  Prompts the user to select from a list, repeating until an item is selected

  ## Options

  - `display`: A function that takes an item and returns a string to display
  """
  def select(prompt, items, opts \\ [])

  def select(_prompt, [], _opts), do: nil
  def select(_prompt, [item], _opts), do: item

  def select(prompt, items, opts) do
    display = Keyword.get(opts, :display, &to_string/1)

    item_numbers =
      items
      |> Enum.with_index()
      |> Enum.map_join("\n", fn {item, index} ->
        if Keyword.has_key?(opts, :default) && item == opts[:default] do
          "#{IO.ANSI.green()}#{index}.#{IO.ANSI.reset()} #{display.(item)} (Default)"
        else
          "#{index}. #{display.(item)}"
        end
      end)

    case String.trim(Mix.shell().prompt(prompt <> "\n" <> item_numbers <> "\nInput number ❯ ")) do
      "" ->
        case Keyword.fetch(opts, :default) do
          {:ok, value} ->
            value

          :error ->
            select(prompt, items, opts)
        end

      item ->
        case Integer.parse(item) do
          {int, ""} ->
            case Enum.at(items, int) do
              nil ->
                Mix.shell().info("Expected one of the provided numbers, got: #{item}")
                select(prompt, items, opts)

              value ->
                value
            end

          _ ->
            Mix.shell().info("Expected a number, got: #{item}")
            select(prompt, items, opts)
        end
    end
  end
end
