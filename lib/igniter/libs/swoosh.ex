# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule Igniter.Libs.Swoosh do
  @moduledoc "Codemods & utilities for working with Swoosh"

  @doc "Lists all project modules that call `use Swoosh.Mailer`."
  @spec list_mailers(Igniter.t()) :: {Igniter.t(), [module()]}
  def list_mailers(igniter) do
    Igniter.Project.Module.find_all_matching_modules(igniter, fn _mod, zipper ->
      move_to_mailer_use(zipper) != :error
    end)
  end

  @doc "Moves to the use statement in a module that matches `use Swoosh.Mailer`"
  @spec move_to_mailer_use(Sourceror.Zipper.t()) ::
          :error | {:ok, Sourceror.Zipper.t()}
  def move_to_mailer_use(zipper) do
    Igniter.Code.Function.move_to_function_call(zipper, :use, 2, fn zipper ->
      Igniter.Code.Function.argument_equals?(
        zipper,
        0,
        Swoosh.Mailer
      )
    end)
  end
end
