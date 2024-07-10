defmodule Igniter.Project.Test do
  @moduledoc "Codemods and utilities for interacting with test and test support files"
  def ensure_test_support(igniter) do
    Igniter.update_elixir_file(igniter, "mix.exs", fn zipper ->
      with {:ok, zipper} <- Igniter.Code.Module.move_to_module_using(zipper, Mix.Project),
           {:ok, zipper} <- Igniter.Code.Module.move_to_def(zipper, :project, 0),
           {:ok, zipper} <-
             Igniter.Code.Common.move_right(zipper, &Igniter.Code.List.list?/1) do
        case Igniter.Code.Keyword.get_key(zipper, :elixirc_paths) do
          {:ok, zipper} ->
            Sourceror.Zipper.top(zipper)

          _ ->
            with {:ok, zipper} <-
                   Igniter.Code.List.append_to_list(
                     zipper,
                     quote(do: {:elixirc_paths, elixirc_paths(Mix.env())})
                   ),
                 zipper <- Sourceror.Zipper.top(zipper),
                 {:ok, zipper} <- Igniter.Code.Common.move_to_do_block(zipper),
                 zipper <-
                   Igniter.Code.Common.add_code(
                     zipper,
                     "defp elixirc_paths(:test), do: [\"lib\", \"test/support\"]"
                   ),
                 zipper <-
                   Igniter.Code.Common.add_code(
                     zipper,
                     "defp elixirc_paths(_), do: [\"lib\"]"
                   ) do
              zipper
            end
        end
      end
    end)
  end
end
