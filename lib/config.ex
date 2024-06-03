defmodule Igniter.Config do
  @moduledoc "Codemods and utilities for configuring Elixir applications."
  require Igniter.Common
  alias Igniter.Common
  alias Sourceror.Zipper

  def configure(igniter, file_path, app_name, config_path, value, updater \\ nil) do
    file_path = Path.join("config", file_path)
    config_path = List.wrap(config_path)
    value = Macro.escape(value)
    updater = updater || fn zipper -> Zipper.replace(zipper, value) end

    igniter
    |> Igniter.include_or_create_elixir_file(file_path, "import Config\n")
    |> Igniter.update_elixir_file(file_path, fn zipper ->
      case try_update_three_arg(zipper, config_path, app_name, updater) do
        {:ok, zipper} ->
          zipper

        :error ->
          case try_update_two_arg(zipper, config_path, app_name, value, updater) do
            {:ok, zipper} ->
              zipper

            :error ->
              # add new code here
              [first | rest] = config_path

              config =
                {:config, [], [app_name, [{first, Igniter.Common.keywordify(rest, value)}]]}

              Igniter.Common.add_code(zipper, config)
          end
      end
    end)
  end

  defp try_update_three_arg(zipper, config_path, app_name, updater) do
    if Enum.count(config_path) == 1 do
      config_item = Enum.at(config_path, 0)

      case Common.move_to_function_call_in_current_scope(zipper, :config, 3, fn function_call ->
             Common.argument_matches_pattern?(function_call, 0, ^app_name) &&
               Common.argument_matches_pattern?(function_call, 1, ^config_item)
           end) do
        :error ->
          :error

        {:ok, zipper} ->
          Common.update_nth_argument(zipper, 2, updater)
      end
    else
      :error
    end
  end

  defp try_update_two_arg(zipper, config_path, app_name, value, updater) do
    case Common.move_to_function_call_in_current_scope(zipper, :config, 2, fn function_call ->
           Common.argument_matches_pattern?(function_call, 0, ^app_name)
         end) do
      :error ->
        :error

      {:ok, zipper} ->
        Common.update_nth_argument(zipper, 1, fn zipper ->
          case Igniter.Common.put_in_keyword(zipper, config_path, value, updater) do
            {:ok, new_zipper} ->
              new_zipper

            _ ->
              zipper
          end
        end)
    end
  end
end
