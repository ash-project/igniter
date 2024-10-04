defmodule Igniter.Project.Application do
  @moduledoc "Codemods and tools for working with Application modules."

  require Igniter.Code.Common
  require Igniter.Code.Function

  alias Igniter.Code.Common
  alias Sourceror.Zipper

  @doc "Returns the name of the current application."
  @spec app_name() :: atom()
  @deprecated "Use `app_name/1` instead."
  def app_name do
    Mix.Project.config()[:app]
  end

  @doc "Returns the name of the application."
  @spec app_name(Igniter.t()) :: atom()
  def app_name(igniter) do
    zipper =
      igniter
      |> Igniter.include_existing_file("mix.exs")
      |> Map.get(:rewrite)
      |> Rewrite.source!("mix.exs")
      |> Rewrite.Source.get(:quoted)
      |> Sourceror.Zipper.zip()

    with {:ok, zipper} <- Igniter.Code.Function.move_to_def(zipper, :project, 0),
         zipper <- Igniter.Code.Common.rightmost(zipper),
         true <- Igniter.Code.List.list?(zipper),
         {:ok, zipper} <- Igniter.Code.Keyword.get_key(zipper, :app),
         {:ok, app_name} when is_atom(app_name) <- Igniter.Code.Common.expand_literal(zipper) do
      app_name
    else
      _ ->
        raise """
        Failed to parse the application name from mix.exs.

        Please ensure that the `project` function in your mix.exs
        file returns a keyword list with an `app` key.
        """
    end
  end

  @doc "Returns the name of the application module."
  def app_module(igniter) do
    zipper =
      igniter
      |> Igniter.include_existing_file("mix.exs")
      |> Map.get(:rewrite)
      |> Rewrite.source!("mix.exs")
      |> Rewrite.Source.get(:quoted)
      |> Sourceror.Zipper.zip()

    with {:ok, zipper} <- Igniter.Code.Function.move_to_def(zipper, :application, 0),
         zipper <- Igniter.Code.Common.rightmost(zipper),
         true <- Igniter.Code.List.list?(zipper),
         {:ok, zipper} <- Igniter.Code.Keyword.get_key(zipper, :mod) do
      case Igniter.Code.Common.expand_literal(zipper) do
        {:ok, app_module} ->
          {:ok, app_module}

        :error ->
          try do
            zipper.node
            |> Code.eval_quoted()
            |> elem(0)
          rescue
            _ ->
              reraise """
                      An application module was configured, but we could not determine its name, cannot continue.
                      """,
                      __STACKTRACE__
          end
      end
    else
      _ ->
        nil
    end
  end

  @doc """
  Adds a new child to the `children` list in the application file

  To pass quoted code as the options, use the following format:

      {module, {:code, quoted_code}}

  i.e

      {MyApp.Supervisor, {:code, quote do
        Application.fetch_env!(:app, :config)
      end}}

  ## Options

  - `after` - A list of other modules that this supervisor should appear after,
     or a function that takes a module and returns `true` if this module should be placed after it.
  - `opts_updater` - A function that takes the current options (second element of the child tuple),
     and returns a new value. If the existing value of the module is not a tuple, the value passed into
     your function will be `[]`. Your function *must* return `{:ok, zipper}` or
     `{:error | :warning, "error_or_warning"}`.

  ## Ordering

  We will put the new child as the earliest item in the list that we can, skipping any modules
  in the `after` option.
  """
  @spec add_new_child(
          Igniter.t(),
          module() | {module, {:code, term()}} | {module, term()},
          opts :: Keyword.t()
        ) ::
          Igniter.t()
  def add_new_child(igniter, to_supervise, opts \\ []) do
    to_perform =
      case app_module(igniter) do
        nil -> {:create_an_app, Igniter.Project.Module.module_name(igniter, "Application")}
        {mod, _} -> {:modify, mod}
        mod -> {:modify, mod}
      end

    opts =
      Keyword.update(opts, :after, fn _ -> false end, fn list ->
        if is_list(list) do
          fn item -> item in list end
        else
          list
        end
      end)

    case to_perform do
      {:create_an_app, mod} ->
        igniter
        |> create_app(mod)
        |> do_add_child(mod, to_supervise, opts)

      {:modify, mod} ->
        do_add_child(igniter, mod, to_supervise, opts)
    end
  end

  def create_app(igniter, application) do
    igniter
    |> point_to_application_in_mix_exs(application)
    |> create_application_file(application)
  end

  def do_add_child(igniter, application, to_supervise, opts) do
    path = Igniter.Project.Module.proper_location(igniter, application, :source_folder)

    to_supervise =
      case to_supervise do
        module when is_atom(module) -> module
        {module, {:code, contents}} when is_atom(module) -> {module, contents}
        {module, contents} -> {module, Macro.escape(contents)}
      end

    to_supervise_module =
      case to_supervise do
        {module, _} -> module
        module -> module
      end

    Igniter.update_elixir_file(igniter, path, fn zipper ->
      with {:ok, zipper} <- Igniter.Code.Module.move_to_module_using(zipper, Application),
           {:ok, zipper} <- Igniter.Code.Function.move_to_def(zipper, :start, 2),
           {:ok, zipper} <-
             Igniter.Code.Function.move_to_function_call_in_current_scope(
               zipper,
               :=,
               [2],
               fn call ->
                 Igniter.Code.Function.argument_matches_pattern?(
                   call,
                   0,
                   {:children, _, context} when is_atom(context)
                 ) &&
                   Igniter.Code.Function.argument_matches_pattern?(call, 1, v when is_list(v))
               end
             ),
           {:ok, zipper} <- Igniter.Code.Function.move_to_nth_argument(zipper, 1) do
        case Igniter.Code.List.move_to_list_item(zipper, fn item ->
               if Igniter.Code.Tuple.tuple?(item) do
                 with {:ok, item} <- Igniter.Code.Tuple.tuple_elem(item, 0),
                      item <- Igniter.Code.Common.expand_alias(item) do
                   Igniter.Code.Common.nodes_equal?(item, to_supervise_module)
                 else
                   _ -> false
                 end
               else
                 item
                 |> Igniter.Code.Common.expand_alias()
                 |> Igniter.Code.Common.nodes_equal?(to_supervise_module)
               end
             end) do
          {:ok, zipper} ->
            if updater = opts[:opts_updater] do
              zipper =
                if Igniter.Code.Tuple.tuple?(zipper) do
                  zipper
                else
                  Zipper.replace(zipper, {zipper.node, []})
                end

              {:ok, zipper} = Igniter.Code.Tuple.tuple_elem(zipper, 1)

              updater.(zipper)
            else
              {:ok, zipper}
            end

          :error ->
            zipper
            |> Zipper.down()
            |> then(fn zipper ->
              case Zipper.down(zipper) do
                nil ->
                  Zipper.insert_child(zipper, to_supervise)

                zipper ->
                  zipper
                  |> skip_after(opts)
                  |> case do
                    {:after, zipper} ->
                      Zipper.insert_right(zipper, to_supervise)

                    {:before, zipper} ->
                      Zipper.insert_left(zipper, to_supervise)
                  end
              end
            end)
        end
      else
        _ ->
          {:warning,
           """
           Could not find a `children = [...]` assignment in the `start` function of the `#{application}` module.
           Please ensure that #{inspect(to_supervise)} is added started by the application `#{application}` manually.
           """}
      end
    end)
  end

  def skip_after(zipper, opts) do
    Igniter.Code.List.do_move_to_list_item(zipper, fn item ->
      with {:is_tuple, true} <- {:is_tuple, Igniter.Code.Tuple.tuple?(item)},
           {:ok, item} <- Igniter.Code.Tuple.tuple_elem(item, 0),
           item <- Igniter.Code.Common.expand_alias(item),
           module when is_atom(module) <- alias_to_mod(item.node),
           true <- opts[:after].(module) do
        true
      else
        {:is_tuple, false} ->
          with item <- Igniter.Code.Common.expand_alias(item),
               module when is_atom(module) <- alias_to_mod(item.node),
               true <- opts[:after].(module) do
            true
          else
            _ ->
              false
          end

        _ ->
          false
      end
    end)
    |> case do
      {:ok, zipper} ->
        case Zipper.right(zipper) do
          nil ->
            {:after, zipper}

          zipper ->
            skip_after(zipper, Keyword.put(opts, :nested?, true))
        end

      :error ->
        if Keyword.get(opts, :nested?) do
          {:after, zipper}
        else
          {:before, zipper}
        end
    end
  end

  def create_application_file(igniter, application) do
    path = Igniter.Project.Module.proper_location(igniter, application)
    supervisor = Igniter.Project.Module.module_name(igniter, "Supervisor")

    contents = """
    defmodule #{inspect(application)} do
      @moduledoc false

      use Application

      @impl true
      def start(_type, _args) do
        children = []

        opts = [strategy: :one_for_one, name: #{inspect(supervisor)}]
        Supervisor.start_link(children, opts)
      end
    end
    """

    Igniter.create_new_file(igniter, path, contents)
  end

  defp point_to_application_in_mix_exs(igniter, application) do
    Igniter.update_elixir_file(igniter, "mix.exs", fn zipper ->
      case Igniter.Code.Module.move_to_module_using(zipper, Mix.Project) do
        {:ok, zipper} ->
          case Igniter.Code.Function.move_to_def(zipper, :application, 0) do
            {:ok, zipper} ->
              zipper
              |> Igniter.Code.Common.rightmost()
              |> Igniter.Code.Keyword.set_keyword_key(:mod, {application, []}, fn z ->
                code =
                  {application, []}
                  |> Sourceror.to_string()
                  |> Sourceror.parse_string!()

                {:ok, Common.replace_code(z, code)}
              end)

            _ ->
              Common.add_code(zipper, """
              def application do
                [
                  mod: {#{inspect(application)}, []}
                ]
              end
              """)
          end

        _ ->
          {:warning,
           """
           No module in `mix.exs` using `Mix.Project` was found. Please update your `mix.exs`
           to point to the application module `#{inspect(application)}`.

           For example:

           def application do
             [
               mod: {#{inspect(application)}, []}
             ]
           end
           """}
      end
    end)
  end

  defp alias_to_mod({:__aliases__, _, parts}), do: Module.concat(parts)
  defp alias_to_mod(v) when is_atom(v), do: v
  defp alias_to_mod(other), do: other
end
