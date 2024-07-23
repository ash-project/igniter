defmodule Igniter.Project.Application do
  @moduledoc "Codemods and tools for working with Application modules."

  require Igniter.Code.Common
  require Igniter.Code.Function

  alias Igniter.Code.Common
  alias Sourceror.Zipper

  @doc "Returns the name of the current application."
  @spec app_name() :: atom()
  def app_name do
    Mix.Project.config()[:app]
  end

  @doc "Adds a new child to the `children` list in the application file"
  @spec add_new_child(Igniter.t(), module() | {module, term()}) :: Igniter.t()
  def add_new_child(igniter, to_supervise) do
    to_perform =
      case mod_definition(igniter) do
        nil -> {:create_an_app, Igniter.Code.Module.module_name("Application")}
        {mod, _} -> {:modify, mod}
        mod -> {:modify, mod}
      end

    case to_perform do
      {:create_an_app, mod} ->
        igniter
        |> create_app(mod)
        |> do_add_child(mod, to_supervise)

      {:modify, mod} ->
        do_add_child(igniter, mod, to_supervise)
    end
  end

  def create_app(igniter, application) do
    igniter
    |> point_to_application_in_mix_exs(application)
    |> create_application_file(application)
  end

  def do_add_child(igniter, application, to_supervise) do
    path = Igniter.Code.Module.proper_location(application)

    diff_checker =
      case to_supervise do
        v when is_atom(v) ->
          &Common.nodes_equal?/2

        {v, _opts} when is_atom(v) ->
          fn
            {item, _}, {right, _} ->
              Common.nodes_equal?(item, right)

            item, {right, _} ->
              Common.nodes_equal?(item, right)

            _, _ ->
              false
          end
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
             ) do
        zipper
        |> Zipper.down()
        |> Zipper.rightmost()
        |> Igniter.Code.List.append_new_to_list(Macro.escape(to_supervise), diff_checker)
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

  defp create_application_file(igniter, application) do
    path = Igniter.Code.Module.proper_location(application)

    contents = """
    defmodule #{inspect(application)} do
      @moduledoc false

      use Application

      @impl true
      def start(_type, _args) do
        children = []

        opts = [strategy: :one_for_one, name: Foo.Supervisor]
        Supervisor.start_link(children, opts)
      end
    end
    """

    Igniter.create_new_elixir_file(igniter, path, contents)
  end

  defp point_to_application_in_mix_exs(igniter, application) do
    Igniter.update_elixir_file(igniter, "mix.exs", fn zipper ->
      case Igniter.Code.Module.move_to_module_using(zipper, Mix.Project) do
        {:ok, zipper} ->
          case Igniter.Code.Function.move_to_def(zipper, :application, 0) do
            {:ok, zipper} ->
              zipper
              |> Zipper.rightmost()
              |> Igniter.Code.Keyword.set_keyword_key(:mod, {application, []}, fn z ->
                {:ok, Common.replace_code(z, {application, []})}
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

  def mod_definition(igniter) do
    zipper =
      igniter
      |> Igniter.include_existing_elixir_file("mix.exs")
      |> Map.get(:rewrite)
      |> Rewrite.source!("mix.exs")
      |> Rewrite.Source.get(:quoted)
      |> Zipper.zip()

    with {:ok, zipper} <- Igniter.Code.Module.move_to_module_using(zipper, Mix.Project),
         {:ok, zipper} <- Igniter.Code.Function.move_to_def(zipper, :application, 0) do
      defined_mod =
        Igniter.Code.List.move_to_list_item(zipper, fn item ->
          if Igniter.Code.Tuple.tuple?(item) do
            case Igniter.Code.Tuple.tuple_elem(item, 0) do
              {:ok, first_elem} ->
                Common.node_matches_pattern?(first_elem, :mod)

              :error ->
                false
            end
          end
        end)

      case defined_mod do
        {:ok, definition} ->
          {{_key, mod}, _} =
            definition
            |> Zipper.node()
            |> Sourceror.to_string()
            |> Code.eval_string()

          mod

        _ ->
          nil
      end
    end
  end
end
