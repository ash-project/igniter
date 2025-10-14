# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs.contributors>
#
# SPDX-License-Identifier: MIT

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

          {:ok, Common.add_code(zipper, code)}

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
  Removes an imported dep from the list of imported deps in the root `.formatter.exs`
  """
  @spec remove_imported_dep(Igniter.t(), dep :: atom) :: Igniter.t()
  def remove_imported_dep(igniter, dep) do
    igniter
    |> Igniter.include_or_create_file(".formatter.exs", @default_formatter)
    |> Igniter.update_elixir_file(".formatter.exs", fn zipper ->
      zipper
      |> Zipper.down()
      |> case do
        nil ->
          {:ok, zipper}

        zipper ->
          zipper
          |> Zipper.rightmost()
          |> Igniter.Code.Keyword.put_in_keyword([:import_deps], [], fn nested_zipper ->
            Igniter.Code.List.remove_from_list(
              nested_zipper,
              &Igniter.Code.Common.nodes_equal?(&1, dep)
            )
          end)
          |> case do
            {:ok, zipper} ->
              zipper

            :error ->
              {:warning,
               """
               Could not remove imported dependency #{inspect(dep)} from `.formatter.exs`.

               Please remove the import manually, i.e replacing


                   import_deps: [:foo, #{inspect(dep)}, :bar]

               with

                   import_deps: [:foo, :bar]
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

          {:ok, Common.add_code(zipper, code)}

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
              {:ok, zipper}

            _ ->
              {:warning,
               """
               Could not add formatter plugin #{inspect(plugin)} into `.formatter.exs`.

               Please add the plugin manually, i.e

                   plugins: [#{inspect(plugin)}]
               """}
          end
      end
    end)
  end

  @doc """
  REmoves a plugin to the list of plugins in the root `.formatter.exs`
  """
  @spec remove_formatter_plugin(Igniter.t(), plugin :: module()) :: Igniter.t()
  def remove_formatter_plugin(igniter, plugin) do
    igniter
    |> Igniter.include_or_create_file(".formatter.exs", @default_formatter)
    |> Igniter.update_elixir_file(".formatter.exs", fn zipper ->
      zipper
      |> Zipper.down()
      |> case do
        nil ->
          {:ok, zipper}

        zipper ->
          zipper
          |> Zipper.rightmost()
          |> Igniter.Code.Keyword.put_in_keyword(
            [:plugins],
            [],
            fn nested_zipper ->
              Igniter.Code.List.remove_from_list(
                nested_zipper,
                &Igniter.Code.Common.nodes_equal?(&1, plugin)
              )
            end
          )
          |> case do
            {:ok, zipper} ->
              zipper

            _ ->
              {:warning,
               """
               Could not remove formatter plugin #{inspect(plugin)} from `.formatter.exs`.

               Please remove the plugin manually, i.e by replacing

                   plugins: [Foo, #{inspect(plugin)}, Bar]

               with

                   plugins: [Foo, Bar]
               """}
          end
      end
    end)
  end
end
