defmodule Igniter.Application do
  @moduledoc "Codemods and tools for working with Application modules."

  require Igniter.Common

  alias Igniter.Common
  alias Sourceror.Zipper

  def app_name do
    Mix.Project.config()[:app]
  end

  def add_child(igniter, to_supervise) do
    project = Mix.Project.get!()

    # TODO: Would be better to check the source and parse the app module out
    # as something else may have set an app module
    to_perform =
      case project.application()[:mod] do
        nil -> {:create_an_app, Igniter.Module.module_name("Application")}
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
    path = Igniter.Module.proper_location(application)

    diff_checker =
      case to_supervise do
        v when is_atom(v) ->
          &Common.equal_modules?/2

        {v, opts} when is_atom(v) ->
          fn
            {item, _}, {right, _} ->
              Common.equal_modules?(item, right)
            item, {right, _} ->
              Common.equal_modules?(item, right)

            _, _ ->
              false
          end
      end

    Igniter.update_elixir_file(igniter, path, fn zipper ->
      with {:ok, zipper} <- Common.move_to_module_using(zipper, Application),
           {:ok, zipper} <- Common.move_to_def(zipper, :start, 2) do
        zipper
        |> Common.move_to_function_call_in_current_scope(:=, [2], fn call ->
          Common.argument_matches_pattern?(call, 0, {:children, _, context} when is_atom(context)) &&
            Common.argument_matches_pattern?(call, 1, v when is_list(v))
        end)
        |> case do
          {:ok, zipper} ->
            zipper
            |> Zipper.down()
            |> Zipper.rightmost()
            |> Igniter.Common.append_new_to_list(to_supervise, diff_checker)

          _ ->
            {:error,
             "Expected the `start/2` function in `#{path}` to have a `children = [...]` assignment."}
        end
      else
        _ ->
          {:error, "Expected `#{path}` to be an Application with a `start` function"}
      end
    end)
  end

  defp create_application_file(igniter, application) do
    path = Igniter.Module.proper_location(application)

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
      case Common.move_to_module_using(zipper, Mix.Project) do
        {:ok, zipper} ->
          case Common.move_to_def(zipper, :application, 0) do
            {:ok, zipper} ->
              zipper
              |> Zipper.rightmost()
              |> Common.set_keyword_key(:mod, {application, []}, fn z ->
                Zipper.replace(z, {application, []})
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
          {:error, "Required a module using `Mix.Project` to exist in `mix.exs`"}
      end
    end)
  end
end
