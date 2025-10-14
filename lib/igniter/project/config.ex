# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule Igniter.Project.Config do
  @moduledoc "Codemods and utilities for modifying Elixir config files."

  require Igniter.Code.Function
  alias Igniter.Code.Common
  alias Sourceror.Zipper

  @type updater :: (Sourceror.Zipper.t() -> {:ok, Sourceror.Zipper.t()}) | :error | nil
  @type after_predicate :: (Sourceror.Zipper.t() -> boolean())

  @type config_group_item ::
          {list(term) | term(), term()} | {list(term) | term(), term(), Keyword.t()}

  @doc """
  Sets a config value in the given configuration file, if it is not already set.

  See `configure/6` for more.

  ## Options

  * `failure_message` - A message to display to the user if the configuration change is unsuccessful.
  * `after` - `t:after_predicate/0`. Moves to the last node that matches the predicate.
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

  @doc """
  Configures a "group" of configurations, which is multiple configurations set at one time.
  If the app + the shared prefix is already configured, then each configuration is added individually,
  and the `comment` for the group is ignored. The sub configurations use `configure`, so if you want to
  not change the value if its already set, use `updater: &{:ok, &1}` in the item opts.

  ## Options

  - `comment` - A comment string to add above the group when its added.
  """
  @spec configure_group(
          Igniter.t(),
          Path.t(),
          atom(),
          shared_prefix :: list(atom),
          list(config_group_item()),
          opts :: Keyword.t()
        ) :: Igniter.t()
  def configure_group(igniter, file_path, app_name, shared_prefix, items, opts \\ []) do
    if Enum.empty?(items) do
      raise ArgumentError, "Must provide at least one item in configure_group/6"
    end

    items =
      Enum.map(items, fn
        {sub_path, value} ->
          {List.wrap(sub_path), value, opts}

        {sub_path, value, opts} ->
          {List.wrap(sub_path), value, opts}
      end)

    if configures_key?(igniter, file_path, app_name, shared_prefix) do
      Enum.reduce(items, igniter, fn {path, value, opts}, igniter ->
        configure(igniter, file_path, app_name, shared_prefix ++ path, value, opts)
      end)
    else
      zipper =
        {:__block__, [], []}
        |> Zipper.zip()

      code_with_configuration_added =
        Enum.reduce_while(items, {:ok, zipper}, fn {path, value, opts}, {:ok, zipper} ->
          case modify_config_code(zipper, shared_prefix ++ path, app_name, value, opts) do
            {:ok, zipper} -> {:cont, {:ok, zipper}}
            other -> {:halt, other}
          end
        end)
        |> case do
          {:ok, zipper} ->
            zipper
            |> Zipper.topmost()
            |> then(fn zipper ->
              if opts[:comment] do
                Igniter.Code.Common.add_comment(zipper, opts[:comment])
              else
                zipper
              end
            end)
            |> Zipper.topmost_root()
            |> then(&{:ok, &1})

          other ->
            other
        end

      case code_with_configuration_added do
        {:warning, warning} ->
          Igniter.add_warning(igniter, warning)

        {:error, error} ->
          Igniter.add_issue(igniter, error)

        {:ok, code_with_configuration_added} ->
          config_file_path = config_file_path(igniter, file_path)

          file_contents = "import Config\n"

          igniter
          |> Igniter.include_or_create_file(config_file_path, file_contents)
          |> ensure_default_configs_exist(file_path)
          |> Igniter.update_elixir_file(config_file_path, fn zipper ->
            case find_config(zipper) do
              nil ->
                {:warning,
                 bad_config_message(
                   app_name,
                   file_path,
                   shared_prefix,
                   Sourceror.to_string(zipper),
                   opts
                 )}

              zipper ->
                Igniter.Code.Common.add_code(zipper, code_with_configuration_added)
            end
          end)
      end
    end
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

    config_file_path = config_file_path(igniter, "runtime.exs")

    igniter
    |> Igniter.create_or_update_elixir_file(config_file_path, default_runtime, &{:ok, &1})
    |> Igniter.update_elixir_file(config_file_path, fn zipper ->
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
          modify_config_code(
            zipper,
            config_path,
            app_name,
            modify_to,
            updater:
              opts[:updater] || fn zipper -> {:ok, Common.replace_code(zipper, modify_to)} end
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
              modify_config_code(
                zipper,
                config_path,
                app_name,
                modify_to,
                updater:
                  opts[:updater] || fn zipper -> {:ok, Common.replace_code(zipper, modify_to)} end
              )

            _ ->
              value =
                case value do
                  {:code, value} -> Sourceror.to_string(value)
                  value -> inspect(value)
                end

              {:warning,
               """
               Could not set #{inspect([app_name | config_path])} in `#{inspect(env)}` of `#{config_file_path}`.

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

  ## Options

  * `failure_message` - A message to display to the user if the configuration change is unsuccessful.
  * `updater` - `t:updater/0`. A function that takes a zipper at a currently configured value and returns a new zipper with the value updated.
  * `after` - `t:after_predicate/0`. Moves to the last node that matches the predicate. Useful to guarantee a `config` is placed after a specific node.
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

    file_path = config_file_path(igniter, file_name)
    config_path = List.wrap(config_path)

    value =
      case value do
        {:code, value} -> value
        value -> Sourceror.parse_string!(Sourceror.to_string(Macro.escape(value)))
      end

    updater = get_updater(opts, value)

    igniter
    |> ensure_default_configs_exist(file_name)
    |> Igniter.include_or_create_file(file_path, file_contents)
    |> Igniter.update_elixir_file(file_path, fn zipper ->
      case find_config(zipper) do
        nil ->
          {:warning, bad_config_message(app_name, file_path, config_path, value, opts)}

        _ ->
          modify_config_code(zipper, config_path, app_name, value,
            updater: updater,
            after: opts[:after]
          )
      end
    end)
  end

  def get_updater(opts, value) do
    updater = opts[:updater] || fn zipper -> {:ok, Common.replace_code(zipper, value)} end

    fn zipper ->
      with :error <- updater.(zipper) do
        :halt
      end
    end
  end

  @doc """
  Removes an applications config completely.
  """
  @spec remove_application_configuration(Igniter.t(), Path.t(), atom()) :: Igniter.t()
  def remove_application_configuration(igniter, file_name, app_name) do
    file_path = config_file_path(igniter, file_name)

    Igniter.update_elixir_file(
      igniter,
      file_path,
      fn zipper ->
        case find_config(zipper) do
          nil -> igniter
          _ -> recursively_remove_configurations(zipper, app_name)
        end
      end,
      required?: false
    )
  end

  defp recursively_remove_configurations(zipper, app_name) do
    case Igniter.Code.Function.move_to_function_call_in_current_scope(
           zipper,
           :config,
           [2, 3],
           &Igniter.Code.Function.argument_equals?(&1, 0, app_name)
         ) do
      :error ->
        zipper

      {:ok, zipper} ->
        zipper
        |> Zipper.remove()
        |> Zipper.top()
        |> recursively_remove_configurations(app_name)
    end
  end

  defp config_file_path(igniter, file_name) do
    case igniter |> Igniter.Project.Application.config_path() |> Path.split() do
      [path] -> [path]
      path -> Enum.drop(path, -1)
    end
    |> Path.join()
    |> Path.join(file_name)
  end

  defp ensure_default_configs_exist(igniter, file_name) do
    if file_name in ["dev.exs", "test.exs", "prod.exs"] do
      igniter
      |> Igniter.include_or_create_file(config_file_path(igniter, "config.exs"), """
      import Config
      """)
      |> ensure_config_evaluates_env()
      |> Igniter.include_or_create_file(config_file_path(igniter, "dev.exs"), """
      import Config
      """)
      |> Igniter.include_or_create_file(config_file_path(igniter, "test.exs"), """
      import Config
      """)
      |> Igniter.include_or_create_file(config_file_path(igniter, "prod.exs"), """
      import Config
      """)
    else
      igniter
    end
  end

  defp ensure_config_evaluates_env(igniter) do
    Igniter.update_elixir_file(igniter, config_file_path(igniter, "config.exs"), fn zipper ->
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

  ## Options

  * `updater` - `t:updater/0`. A function that takes a zipper at a currently configured value and returns a new zipper with the value updated.
  * `after` - `t:after_predicate/0`. Moves to the last node that matches the predicate.
  """
  @spec modify_configuration_code(
          Zipper.t(),
          list(atom),
          atom(),
          term(),
          opts :: Keyword.t()
        ) :: Zipper.t()
  @deprecated "Use `modify_config_code/5`"
  def modify_configuration_code(zipper, config_path, app_name, value, opts \\ [])

  def modify_configuration_code(zipper, config_path, app_name, value, updater)
      when is_function(updater) do
    IO.warn("updater argument is deprecated, please use opts updater: fun instead")
    modify_configuration_code(zipper, config_path, app_name, value, updater: updater)
  end

  def modify_configuration_code(zipper, config_path, app_name, value, opts) do
    case modify_config_code(zipper, config_path, app_name, value, opts) do
      {:ok, zipper} -> zipper
      _ -> zipper
    end
  end

  @doc """
  Modifies elixir configuration code starting at the configured zipper.

  If you want to set configuration, use `configure/6` or `configure_new/5` instead. This is a lower-level
  tool for modifying configuration files when you need to adjust some specific part of them.

  ## Options

  * `updater` - `t:updater/0`. A function that takes a zipper at a currently configured value and returns a new zipper with the value updated.
  * `after` - `t:after_predicate/0`. Moves to the last node that matches the predicate.
  """

  @spec modify_configuration_code(
          Zipper.t(),
          list(atom),
          atom(),
          term(),
          opts :: Keyword.t()
        ) :: {:ok, Zipper.t()} | :error | {:warning, String.t()} | {:error, String.t()}
  def modify_config_code(zipper, config_path, app_name, value, opts \\ []) do
    updater = get_updater(opts, value)

    Igniter.Code.Common.within(zipper, fn zipper ->
      zipper = move_to_after(zipper, opts[:after])

      case try_update_three_arg(zipper, config_path, app_name, value, updater) do
        :halt ->
          {:ok, zipper}

        {:error, error} ->
          {:error, error}

        {:warning, warning} ->
          {:warning, warning}

        {:ok, zipper} ->
          {:ok, zipper}

        :error ->
          case try_update_two_arg(zipper, config_path, app_name, value, updater) do
            :halt ->
              {:ok, zipper}

            {:error, error} ->
              {:error, error}

            {:warning, warning} ->
              {:warning, warning}

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
                      {:ok, Common.add_code(zipper, config, placement: :before)}
                  end

                :error ->
                  zipper
                  |> Zipper.right()
                  |> case do
                    nil ->
                      {:ok, Common.add_code(zipper, config)}

                    zipper ->
                      {:ok, Common.add_code(zipper, config, placement: :before)}
                  end
              end
          end
      end
    end)
    |> case do
      :halt -> {:ok, zipper}
      other -> other
    end
  end

  defp move_to_after(zipper, pred) when is_function(pred, 1) do
    case Common.move_to_last(zipper, pred) do
      {:ok, zipper} -> zipper
      :error -> zipper
    end
  end

  defp move_to_after(zipper, _pred), do: zipper

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
    config_file_path = config_file_path(igniter, config_file_name)

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
          if path == [] do
            case Igniter.Code.Function.move_to_nth_argument(zipper, 2) do
              {:ok, zipper} ->
                updater.(zipper)

              _ ->
                :error
            end
          else
            with {:ok, zipper} <- Igniter.Code.Function.move_to_nth_argument(zipper, 2),
                 {:ok, zipper} <-
                   Igniter.Code.Keyword.put_in_keyword(zipper, path, value, updater) do
              {:ok, zipper}
            else
              other ->
                other
            end
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

  defp find_config(zipper) do
    Zipper.find(zipper, fn
      {:import, _, [Config]} ->
        true

      {:import, _, [{:__aliases__, _, [:Config]}]} ->
        true

      _ ->
        false
    end)
  end
end
