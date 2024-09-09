defmodule Igniter.Project.Formatter do
  @moduledoc "Codemods and utilities for interacting with `.formatter.exs` files"
  alias Igniter.Code.Common
  alias Sourceror.Zipper

  @default_formatter """
  # Used by "mix format"
  [
    inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
  ]
  """

  @doc """
  Adds a new dep to the list of imported deps in the root `.formatter.exs`
  """
  @spec import_dep(Igniter.t(), dep :: atom) :: Igniter.t()
  def import_dep(igniter, dep) do
    igniter
    |> Igniter.include_or_create_file(".formatter.exs", @default_formatter)
    |> Igniter.update_elixir_file(".formatter.exs", fn zipper ->
      zipper
      |> Zipper.down()
      |> case do
        nil ->
          code =
            quote do
              [import_deps: [unquote(dep)]]
            end

          Common.add_code(zipper, code)

        zipper ->
          zipper
          |> Zipper.rightmost()
          |> Igniter.Code.Keyword.put_in_keyword([:import_deps], [dep], fn nested_zipper ->
            Igniter.Code.List.prepend_new_to_list(
              nested_zipper,
              dep
            )
          end)
          |> case do
            {:ok, zipper} ->
              zipper

            :error ->
              {:warning,
               """
               Could not import dependency #{inspect(dep)} into `.formatter.exs`.

               Please add the import manually, i.e

                   import_deps: [#{inspect(dep)}]
               """}
          end
      end
    end)
  end

  @doc """
  Adds a new plugin to the list of plugins in the root `.formatter.exs`
  """
  @spec add_formatter_plugin(Igniter.t(), plugin :: module()) :: Igniter.t()
  def add_formatter_plugin(igniter, plugin) do
    igniter
    |> Igniter.include_or_create_file(".formatter.exs", @default_formatter)
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
          |> Common.add_code(code)

        zipper ->
          zipper
          |> Zipper.rightmost()
          |> Igniter.Code.Keyword.put_in_keyword(
            [:plugins],
            [plugin],
            fn nested_zipper ->
              Igniter.Code.List.prepend_new_to_list(
                nested_zipper,
                plugin
              )
            end
          )
          |> case do
            {:ok, zipper} ->
              zipper

            _ ->
              {:warning,
               """
               Could not add formatter plugin #{inspect(plugin)} into `.formatter.exs`.

               Please add the import manually, i.e

                   plugins: [#{inspect(plugin)}]
               """}
          end
      end
    end)
  end
end
