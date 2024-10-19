defmodule Igniter.Project.Config do
  @moduledoc "Codemods and utilities for modifying Elixir config files."

  require Igniter.Code.Function
  alias Igniter.Code.Common
  alias Sourceror.Zipper

  @doc """
  Sets a config value in the given configuration file, if it is not already set.

  See `configure/6` for more.

  ## Opts

  * `failure_message` - A message to display to the user if the configuration change is unsuccessful.
  """
  @spec configure_new(Igniter.t(), Path.t(), atom(), list(atom), term(), opts :: Keyword.t()) ::
          Igniter.t()
  def configure_new(igniter, file_path, app_name, config_path, value, opts \\ []) do
    configure(
      igniter,
      file_path,
      app_name,
      config_path,
      value,
      Keyword.put(opts, :updater, &{:ok, &1})
    )
  end

  @spec configure_runtime_env(
          Igniter.t(),
          atom(),
          atom(),
          list(atom),
          term(),
          opts :: Keyword.t()
        ) ::
          Igniter.t()
  def configure_runtime_env(igniter, env, app_name, config_path, value, opts \\ []) do
    default_runtime =
      """
      import Config

      if config_env() == #{inspect(env)} do
      end
      """

    igniter
    |> Igniter.create_or_update_elixir_file("config/runtime.exs", default_runtime, &{:ok, &1})
    |> Igniter.update_elixir_file("config/runtime.exs", fn zipper ->
      patterns = [
        """
        if config_env() == #{inspect(env)} do
          __cursor__()
        end
        """,
        """
        if #{inspect(env)} == config_env() do
          __cursor__()
        end
        """
      ]

      modify_to =
        case value do
          {:code, value} -> value
          value -> Sourceror.parse_string!(Sourceror.to_string(Macro.escape(value)))
        end

      zipper
      |> Igniter.Code.Common.move_to_cursor_match_in_scope(patterns)
      |> case do
        {:ok, zipper} ->
          modify_configuration_code(
            zipper,
            config_path,
            app_name,
            modify_to,
            opts[:updater] || (&{:ok, &1})
          )

        :error ->
          zipper
          |> Igniter.Code.Common.add_code("""
          if config_env() == #{inspect(env)} do
          end
          """)
          |> Igniter.Code.Common.move_to_cursor_match_in_scope(patterns)
          |> case do
            {:ok, zipper} ->
              modify_configuration_code(
                zipper,
                config_path,
                app_name,
                modify_to,
                opts[:updater] || (&{:ok, &1})
              )

            _ ->
              value =
                case value do
                  {:code, value} -> Sourceror.to_string(value)
                  value -> inspect(value)
                end

              {:warning,
               """
               Could not set #{inspect([app_name | config_path])} in `#{inspect(env)}` of `config/runtime.exs`.

               ```elixir
               # in `runtime.exs`
               if config_env() == #{inspect(env)} do
                 # Please configure #{inspect([app_name | config_path])} it to the following value
                 #{value}
               end
               ```
               """}
          end
      end
    end)
  end

  @doc """
  Sets a config value in the given configuration file, updating it with `updater` if it is already set.

  If the value is source code, pass `{:code, value}`, otherwise pass just the value.

  To produce this source code, we suggest using `Sourceror.parse_string!`. For example:

  ```elixir
  |> Igniter.Project.Config.configure(
    "fake.exs",
    :tailwind,
    [:default, :args],
    {:code,
     Sourceror.parse_string!(\"\"\"
     ~w(--config=tailwind.config.js --input=css/app.css --output=../output/assets/app.css)
     \"\"\")}
  )
  ```

  ## Opts

  * `:updater` - A function that takes a zipper at a currently configured value and returns a new zipper with the value updated.
  * `failure_message` - A message to display to the user if the configuration change is unsuccessful.
  """
  @spec configure(
          Igniter.t(),
          Path.t(),
          atom(),
          list(atom),
          term(),
          opts :: Keyword.t()
        ) :: Igniter.t()
  def configure(igniter, file_name, app_name, config_path, value, opts \\ []) do
    file_contents = "import Config\n"

    file_path = Path.join("config", file_name)
    config_path = List.wrap(config_path)

    value =
      case value do
        {:code, value} -> value
        value -> Sourceror.parse_string!(Sourceror.to_string(Macro.escape(value)))
      end

    updater = opts[:updater] || fn zipper -> {:ok, Common.replace_code(zipper, value)} end

    igniter
    |> ensure_default_configs_exist(file_path)
    |> Igniter.include_or_create_file(file_path, file_contents)
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
          {:warning, bad_config_message(app_name, file_path, config_path, value, opts)}

        _ ->
          modify_configuration_code(zipper, config_path, app_name, value, updater)
      end
    end)
  end

  defp ensure_default_configs_exist(igniter, file)
       when file in ["config/dev.exs", "config/test.exs", "config/prod.exs"] do
    igniter
    |> Igniter.include_or_create_file("config/config.exs", """
    import Config
    """)
    |> ensure_config_evaluates_env()
    |> Igniter.include_or_create_file("config/dev.exs", """
    import Config
    """)
    |> Igniter.include_or_create_file("config/test.exs", """
    import Config
    """)
    |> Igniter.include_or_create_file("config/prod.exs", """
    import Config
    """)
  end

  defp ensure_default_configs_exist(igniter, _), do: igniter

  defp ensure_config_evaluates_env(igniter) do
    Igniter.update_elixir_file(igniter, "config/config.exs", fn zipper ->
      case Igniter.Code.Function.move_to_function_call_in_current_scope(zipper, :import_config, 1) do
        {:ok, _} ->
          {:ok, zipper}

        _ ->
          {:ok,
           Igniter.Code.Common.add_code(zipper, """
           import_config "\#{config_env()}.exs"
           """)}
      end
    end)
  end

  defp bad_config_message(app_name, file_path, config_path, value, opts) do
    path =
      config_path
      |> keywordify(value)

    code =
      quote do
        config unquote(app_name), unquote(path)
      end

    message =
      if opts[:failure_message] do
        """


        #{opts[:failure_message]}
        """
      else
        ""
      end

    or_update =
      if opts[:updater] do
        " or update"
      else
        ""
      end

    """
    Please set#{or_update} the following config in #{file_path}:

        #{Macro.to_string(code)}#{String.trim_trailing(message)}
    """
  end

  defp keywordify([], value), do: value
  defp keywordify([key | rest], value), do: [{key, keywordify(rest, value)}]

  @doc """
  Modifies elixir configuration code starting at the configured zipper.

  If you want to set configuration, use `configure/6` or `configure_new/5` instead. This is a lower-level
  tool for modifying configuration files when you need to adjust some specific part of them.
  """
  @spec modify_configuration_code(
          Zipper.t(),
          list(atom),
          atom(),
          term(),
          (Zipper.t() -> {:ok, Zipper.t()} | :error) | nil
        ) :: Zipper.t()
  def modify_configuration_code(zipper, config_path, app_name, value, updater \\ nil) do
    updater = updater || fn zipper -> {:ok, Common.replace_code(zipper, value)} end

    Igniter.Code.Common.within(zipper, fn zipper ->
      case try_update_three_arg(zipper, config_path, app_name, value, updater) do
        {:ok, zipper} ->
          {:ok, zipper}

        :error ->
          case try_update_two_arg(zipper, config_path, app_name, value, updater) do
            {:ok, zipper} ->
              {:ok, zipper}

            :error ->
              [first | rest] = config_path

              config =
                if simple_atom(first) do
                  {:config, [],
                   [app_name, [{first, Igniter.Code.Keyword.keywordify(rest, value)}]]}
                else
                  {:config, [], [app_name, first, Igniter.Code.Keyword.keywordify(rest, value)]}
                end

              case Igniter.Code.Function.move_to_function_call_in_current_scope(
                     zipper,
                     :import,
                     1,
                     fn function_call ->
                       Igniter.Code.Function.argument_matches_predicate?(
                         function_call,
                         0,
                         &Common.nodes_equal?(&1, Config)
                       )
                     end
                   ) do
                {:ok, zipper} ->
                  zipper
                  |> Zipper.right()
                  |> case do
                    nil ->
                      {:ok, Common.add_code(zipper, config)}

                    zipper ->
                      {:ok, Common.add_code(zipper, config, :before)}
                  end

                :error ->
                  zipper
                  |> Zipper.right()
                  |> case do
                    nil ->
                      {:ok, Common.add_code(zipper, config)}

                    zipper ->
                      {:ok, Common.add_code(zipper, config, :before)}
                  end
              end
          end
      end
    end)
    |> case do
      {:ok, zipper} -> zipper
      :error -> zipper
    end
  end

  @doc """
  Checks if either `config :root_key, _` or `config :root_key, _, _` is present
  in the provided config file.

  Note: The config file name should _not_ include the `config/` prefix.
  """
  @spec configures_root_key?(Igniter.t(), String.t(), atom()) :: boolean()
  def configures_root_key?(igniter, config_file_name, root_key) do
    case load_config_zipper(igniter, config_file_name) do
      nil -> false
      zipper -> configures_root_key?(zipper, root_key)
    end
  end

  @doc """
  Same as `configures_root_key?/3` but accepts a Zipper instead.
  """
  @spec configures_root_key?(Zipper.t(), atom()) :: boolean()
  def configures_root_key?(%Zipper{} = zipper, root_key) do
    with :error <-
           Igniter.Code.Function.move_to_function_call_in_current_scope(
             zipper,
             :config,
             2,
             &Igniter.Code.Function.argument_equals?(&1, 0, root_key)
           ),
         :error <-
           Igniter.Code.Function.move_to_function_call_in_current_scope(
             zipper,
             :config,
             3,
             &Igniter.Code.Function.argument_equals?(&1, 0, root_key)
           ) do
      false
    else
      {:ok, _zipper} -> true
    end
  end

  @doc """
  If the last argument is key, checks if either `config :root_key, :key, ...`
  or `config :root_key, key: ...` is set.

  If the last argument is a keyword path, checks if
  `config :root_key, path_head, [...]` defines `path_rest` or if
  `config :root_key, [...]` defines `path`, where `path_head` is the first
  element of `path` and `path_rest` are the remaining elements.

  Note: `config_file_name` should _not_ include the `config/` prefix.
  """
  @spec configures_key?(
          Igniter.t(),
          String.t(),
          atom(),
          atom() | list(atom())
        ) :: boolean()
  def configures_key?(igniter, config_file_name, root_key, key_or_path) do
    case load_config_zipper(igniter, config_file_name) do
      nil -> false
      zipper -> configures_key?(zipper, root_key, key_or_path)
    end
  end

  @doc """
  Same as `configures_key?/4` but accepts a Zipper.
  """
  @spec configures_key?(Zipper.t(), atom(), atom() | list(atom())) :: boolean()
  def configures_key?(zipper, root_key, key_or_path)

  def configures_key?(zipper = %Zipper{}, root_key, key) when is_atom(key) do
    configures_key?(zipper, root_key, List.wrap(key))
  end

  def configures_key?(zipper = %Zipper{}, root_key, path) when is_list(path) do
    with :error <-
           Igniter.Code.Function.move_to_function_call_in_current_scope(
             zipper,
             :config,
             2,
             fn function_call ->
               Igniter.Code.Function.argument_equals?(function_call, 0, root_key) and
                 Igniter.Code.Function.argument_matches_predicate?(
                   function_call,
                   1,
                   fn argument_zipper ->
                     Igniter.Code.Keyword.keyword_has_path?(argument_zipper, path)
                   end
                 )
             end
           ),
         :error <-
           Igniter.Code.Function.move_to_function_call_in_current_scope(
             zipper,
             :config,
             3,
             fn function_call ->
               case path do
                 [key] ->
                   Igniter.Code.Function.argument_equals?(function_call, 0, root_key) and
                     Igniter.Code.Function.argument_equals?(function_call, 1, key)

                 [path_head | path_rest] ->
                   Igniter.Code.Function.argument_equals?(function_call, 0, root_key) and
                     Igniter.Code.Function.argument_equals?(function_call, 1, path_head) and
                     Igniter.Code.Function.argument_matches_predicate?(
                       function_call,
                       2,
                       fn argument_zipper ->
                         Igniter.Code.Keyword.keyword_has_path?(argument_zipper, path_rest)
                       end
                     )
               end
             end
           ) do
      false
    else
      {:ok, _zipper} -> true
    end
  end

  @doc "Returns `true` if the given configuration path is set somewhere after the provided zipper, or in the given configuration file."
  @deprecated "Use configures_root_key?/3 or configures_key?/4 instead."
  @spec configures?(Igniter.t(), String.t(), list(atom), atom()) :: boolean()
  def configures?(igniter, config_file_name, path, app_name) do
    case load_config_zipper(igniter, config_file_name) do
      nil -> false
      zipper -> configures?(zipper, path, app_name)
    end
  end

  @spec configures?(Zipper.t(), list(atom), atom()) :: boolean()
  @deprecated "Use configures_root_key?/2 or configures_key?/3 instead."
  def configures?(zipper, path, app_name) do
    case path do
      [] ->
        configures_root_key?(zipper, app_name)

      path ->
        configures_key?(zipper, app_name, path)
    end
  end

  defp load_config_zipper(igniter, config_file_name) do
    config_file_path = Path.join("config", config_file_name)

    igniter =
      Igniter.include_existing_file(igniter, config_file_path, required?: false)

    case Rewrite.source(igniter.rewrite, config_file_path) do
      {:ok, source} ->
        source
        |> Rewrite.Source.get(:quoted)
        |> Zipper.zip()

      _ ->
        nil
    end
  end

  defp try_update_three_arg(zipper, config_path, app_name, value, updater) do
    if Enum.count(config_path) == 1 and simple_atom(Enum.at(config_path, 0)) do
      config_item = Enum.at(config_path, 0)

      case Igniter.Code.Function.move_to_function_call_in_current_scope(
             zipper,
             :config,
             3,
             fn function_call ->
               Igniter.Code.Function.argument_equals?(function_call, 0, app_name) &&
                 Igniter.Code.Function.argument_equals?(function_call, 1, config_item)
             end
           ) do
        :error ->
          :error

        {:ok, zipper} ->
          Igniter.Code.Function.update_nth_argument(zipper, 2, updater)
      end
    else
      [config_item | path] = config_path

      case Igniter.Code.Function.move_to_function_call_in_current_scope(
             zipper,
             :config,
             3,
             fn function_call ->
               Igniter.Code.Function.argument_equals?(function_call, 0, app_name) &&
                 (Igniter.Code.Function.argument_equals?(function_call, 1, config_item) ||
                    Igniter.Code.Function.argument_matches_predicate?(
                      function_call,
                      1,
                      &Common.nodes_equal?(&1, config_item)
                    ))
             end
           ) do
        :error ->
          :error

        {:ok, zipper} ->
          with {:ok, zipper} <- Igniter.Code.Function.move_to_nth_argument(zipper, 2),
               {:ok, zipper} <- Igniter.Code.Keyword.put_in_keyword(zipper, path, value, updater) do
            {:ok, zipper}
          else
            _ ->
              :error
          end
      end
    end
  end

  defp try_update_two_arg(zipper, config_path, app_name, value, updater) do
    if simple_atom(Enum.at(config_path, 0)) do
      case Igniter.Code.Function.move_to_function_call_in_current_scope(
             zipper,
             :config,
             2,
             fn function_call ->
               Igniter.Code.Function.argument_equals?(function_call, 0, app_name)
             end
           ) do
        :error ->
          :error

        {:ok, zipper} ->
          Igniter.Code.Function.update_nth_argument(
            zipper,
            1,
            &Igniter.Code.Keyword.put_in_keyword(&1, config_path, value, updater)
          )
      end
    else
      :error
    end
  end

  defp simple_atom(value) do
    is_atom(value) and Regex.match?(~r/^[a-z_][a-zA-Z0-9_?!]*$/, to_string(value))
  end
end
