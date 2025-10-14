# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule Igniter.Upgrades.Igniter do
  @moduledoc false

  alias Igniter.Code.Common
  alias Igniter.Code.Function
  alias Igniter.Code.Module
  alias Sourceror.Zipper

  require Common
  require Function

  @doc """
  Rewrites deprecated `igniter/2` callback to `igniter/1` if the module
  is an `Igniter.Mix.Task`.
  """
  @spec rewrite_deprecated_igniter_callback(Zipper.t()) :: {:ok, Zipper.t()} | :error
  def rewrite_deprecated_igniter_callback(%Zipper{} = zipper) do
    with {:ok, zipper} <- Module.move_to_module_using(zipper, [Igniter.Mix.Task]),
         {:ok, zipper} <- Common.move_to_pattern(zipper, {:def, _, [{:igniter, _, [_, _]} | _]}) do
      with :error <- remove_ignored_argv(zipper),
           :error <- replace_generated_argv_usage(zipper) do
        {:ok, zipper}
      end
    else
      _ -> {:ok, zipper}
    end
  end

  defp remove_ignored_argv(zipper) do
    with %Zipper{node: {argv_var, _, nil}} <-
           Zipper.search_pattern(zipper, "igniter(__, __cursor__())"),
         "_" <> _ <- to_string(argv_var) do
      remove_argv_arg(zipper)
    else
      _ -> :error
    end
  end

  defp replace_generated_argv_usage(zipper) do
    with {:ok, zipper} <- remove_argv_arg(zipper),
         {:ok, zipper} <- Common.move_to_do_block(zipper),
         zipper <- Common.maybe_move_to_block(zipper),
         true <- generated_argv_usage?(zipper) do
      zipper =
        zipper
        |> Zipper.remove()
        |> Zipper.next()
        |> Common.replace_code("""
        arguments = igniter.args.positional
        options = igniter.args.options
        argv = igniter.args.argv_flags
        """)

      {:ok, zipper}
    else
      _ -> :error
    end
  end

  defp generated_argv_usage?(zipper) do
    with ^zipper <- Zipper.search_pattern(zipper, "{arguments, argv} = positional_args!(argv)"),
         {:ok, zipper} <- Common.move_right(zipper, 1),
         ^zipper <- Zipper.search_pattern(zipper, "options = options!(argv)") do
      true
    else
      _ -> false
    end
  end

  defp remove_argv_arg(zipper) do
    Common.within(zipper, fn zipper ->
      case Zipper.search_pattern(zipper, "igniter(__, __cursor__())") do
        %Zipper{} = zipper -> {:ok, Zipper.remove(zipper)}
        _ -> :error
      end
    end)
  end
end
