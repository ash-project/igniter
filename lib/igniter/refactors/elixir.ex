# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule Igniter.Refactors.Elixir do
  @moduledoc "Refactors for changes in Elixir"

  @bool_operators [
    :>,
    :>=,
    :<,
    :<=,
    :in
  ]
  @guards [
    :is_atom,
    :is_boolean,
    :is_nil,
    :is_number,
    :is_integer,
    :is_float,
    :is_binary,
    :is_map,
    :is_struct,
    :is_non_struct_map,
    :is_exception,
    :is_list,
    :is_tuple,
    :is_function,
    :is_reference,
    :is_pid,
    :is_port
  ]

  @spec unless_to_if_not(Igniter.t()) :: Igniter.t()
  def unless_to_if_not(igniter) do
    Igniter.update_all_elixir_files(igniter, fn zipper ->
      # TODO: remap references in addition to calls
      Igniter.Code.Common.update_all_matches(
        zipper,
        fn zipper ->
          Igniter.Code.Function.function_call?(zipper, :unless, 2)
        end,
        fn zipper ->
          with {:ok, zipper} <-
                 Igniter.Refactors.Rename.do_rename(
                   zipper,
                   {Kernel, :unless},
                   {Kernel, :if},
                   2
                 ),
               {:ok, zipper} <- Igniter.Code.Function.move_to_nth_argument(zipper, 0) do
            new_node =
              case zipper.node do
                {:in, meta, [l, r]} ->
                  {:not, meta, [{:in, [], [l, r]}]}

                {:==, meta, [l, r]} ->
                  {:!=, meta, [l, r]}

                {:!=, meta, [l, r]} ->
                  {:==, meta, [l, r]}

                {:===, meta, [l, r]} ->
                  {:!==, meta, [l, r]}

                {:!==, meta, [l, r]} ->
                  {:===, meta, [l, r]}

                {neg, _, [condition]} when neg in [:!, :not] ->
                  condition

                {op, _, [_, _]} when op in @bool_operators ->
                  {:not, [], [zipper.node]}

                {guard, _, [_ | _]} when guard in @guards ->
                  {:not, [], [zipper.node]}

                _ ->
                  {:!, [], [zipper.node]}
              end

            {:ok,
             Igniter.Code.Common.replace_code(
               zipper,
               new_node
             )}
          else
            :error ->
              {:warning,
               """
               Could not update the unless statement:

               #{Igniter.Util.Debug.code_at_node(zipper)}
               """}
          end
        end
      )
    end)
  end
end
