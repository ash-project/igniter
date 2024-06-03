defmodule Igniter.Formatter do
  @moduledoc "Codemods and utilities for interacting with `.formatter.exs` files"
  alias Igniter.Common
  alias Sourceror.Zipper

  @default_formatter """
  # Used by "mix format"
  [
    inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
  ]
  """

  def import_dep(igniter, dep) do
    igniter
    |> Igniter.include_or_create_elixir_file(".formatter.exs", @default_formatter)
    |> Igniter.update_elixir_file(".formatter.exs", fn zipper ->
      zipper
      |> Zipper.down()
      |> case do
        nil ->
          code =
            quote do
              [import_deps: [unquote(dep)]]
            end

          Igniter.Common.add_code(zipper, code)

        zipper ->
          zipper
          |> Zipper.rightmost()
          |> Common.put_in_keyword([:import_deps], [dep], fn nested_zipper ->
            Igniter.Common.prepend_new_to_list(
              nested_zipper,
              dep
            )
          end)
          |> case do
            {:ok, zipper} ->
              zipper

            :error ->
              zipper
          end
      end
    end)
  end

  def add_formatter_plugin(igniter, plugin) do
    igniter
    |> Igniter.include_or_create_elixir_file(".formatter.exs", @default_formatter)
    |> Igniter.update_elixir_file(".formatter.exs", fn zipper ->
      zipper
      |> Zipper.down()
      |> case do
        nil ->
          code =
            quote do
              [plugins: [unquote(plugin)]]
            end

          zipper
          |> Igniter.Common.add_code(code)

        zipper ->
          zipper
          |> Zipper.rightmost()
          |> Common.put_in_keyword([:plugins], [Spark.Formatter], fn nested_zipper ->
            Igniter.Common.prepend_new_to_list(
              nested_zipper,
              Spark.Formatter,
              &Igniter.Common.equal_modules?/2
            )
          end)
          |> case do
            {:ok, zipper} ->
              zipper

            _ ->
              zipper
          end
      end
    end)
  end
end
