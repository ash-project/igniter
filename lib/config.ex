defmodule Igniter.Config do
  @moduledoc "Codemods and utilities for configuring Elixir applications."
  require Igniter.Common
  alias Igniter.Common
  alias Sourceror.Zipper

  def configure_new(igniter, file_path, app_name, config_path, value) do
    configure(igniter, file_path, app_name, config_path, value, & &1)
  end

  def configure(igniter, file_path, app_name, config_path, value, updater \\ nil) do
    file_contents =
      if file_path == "config.exs" do
        """
        import Config

        # Import environment specific config. This must remain at the bottom
        # of this file so it overrides the configuration defined above.
        import_config "\#{config_env()}.exs"
        """
      else
        "import Config\n"
      end

    file_path = Path.join("config", file_path)
    config_path = List.wrap(config_path)

    value =
      case value do
        {:code, value} -> value
        value -> Macro.escape(value)
      end

    updater = updater || fn zipper -> Zipper.replace(zipper, value) end

    igniter
    |> Igniter.include_or_create_elixir_file(file_path, file_contents)
    |> Igniter.update_elixir_file(file_path, fn zipper ->
      case Zipper.find(zipper, fn
             {:import, _, [Config]} ->
               true

             {:import, _, [{:__aliases__, _, [:Config]}]} ->
               true

             _ ->
               false
           end) do
        nil ->
          {:error, "No call to `import Config` found in configuration file"}

        zipper ->
          modify_configuration_code(zipper, config_path, app_name, value, updater)
      end
    end)
  end

  def modify_configuration_code(zipper, config_path, app_name, value, updater \\ nil) do
    updater = updater || fn zipper -> Zipper.replace(zipper, value) end

    case try_update_three_arg(zipper, config_path, app_name, updater) do
      {:ok, zipper} ->
        zipper

      :error ->
        case try_update_two_arg(zipper, config_path, app_name, value, updater) do
          {:ok, zipper} ->
            zipper

          :error ->
            [first | rest] = config_path

            config =
              {:config, [], [app_name, [{first, Igniter.Common.keywordify(rest, value)}]]}

            case Common.move_to_function_call_in_current_scope(
                   zipper,
                   :import,
                   1,
                   fn function_call ->
                     Common.argument_matches_predicate?(
                       function_call,
                       0,
                       &Common.equal_modules?(&1, Config)
                     )
                   end
                 ) do
              {:ok, zipper} ->
                zipper
                |> Zipper.right()
                |> case do
                  nil ->
                    Igniter.Common.add_code(zipper, config)

                  zipper ->
                    Igniter.Common.add_code(zipper, config, :before)
                end
            end
        end
    end
  end

  def configures?(zipper, config_path, app_name) do
    if Enum.count(config_path) == 1 do
      config_item = Enum.at(config_path, 0)

      case Common.move_to_function_call_in_current_scope(zipper, :config, 3, fn function_call ->
             Common.argument_matches_pattern?(function_call, 0, ^app_name) &&
               Common.argument_matches_pattern?(function_call, 1, ^config_item)
           end) do
        :error ->
          false

        {:ok, _zipper} ->
          true
      end
    else
      case Common.move_to_function_call_in_current_scope(zipper, :config, 2, fn function_call ->
             Common.argument_matches_pattern?(function_call, 0, ^app_name)
           end) do
        :error ->
          :error

        {:ok, zipper} ->
          Common.argument_matches_predicate?(zipper, 1, fn zipper ->
            Igniter.Common.keyword_has_path?(zipper, config_path)
          end)
      end
    end
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
