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
    with {:ok, {argv_var, _, nil}} <- fetch_argv_arg(zipper),
         "_" <> _ <- to_string(argv_var) do
      remove_argv_arg(zipper)
    else
      _ -> :error
    end
  end

  defp replace_generated_argv_usage(zipper) do
    with {:ok, {:argv, _, nil}} <- fetch_argv_arg(zipper),
         {:ok, zipper} <- remove_argv_arg(zipper),
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
    line_one_match? =
      Function.function_call?(zipper, :=, 2) and
        Function.argument_matches_pattern?(zipper, 0, {{:arguments, _, nil}, {:argv, _, nil}}) and
        Function.argument_matches_predicate?(
          zipper,
          1,
          &Common.node_matches_pattern?(&1, {:positional_args!, _, [{:argv, _, nil}]})
        )

    with true <- line_one_match?,
         {:ok, zipper} <- Common.move_right(zipper, 1) do
      Function.function_call?(zipper, :=, 2) and
        Function.argument_matches_pattern?(zipper, 0, {:options, _, nil}) and
        Function.argument_matches_predicate?(
          zipper,
          1,
          &Common.node_matches_pattern?(&1, {:options!, _, [{:argv, _, nil}]})
        )
    else
      _ -> false
    end
  end

  defp remove_argv_arg(zipper) do
    Common.within(zipper, fn zipper ->
      with {:ok, argv} <- fetch_argv_arg(zipper),
           {:ok, zipper} <- Common.move_to_pattern(zipper, ^argv) do
        {:ok, Zipper.remove(zipper)}
      end
    end)
  end

  defp fetch_argv_arg(zipper) do
    case zipper.node do
      {:def, _, [{:igniter, _, [_, argv]} | _]} -> {:ok, argv}
      _ -> :error
    end
  end
end
