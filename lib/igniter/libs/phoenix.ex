defmodule Igniter.Libs.Phoenix do
  @moduledoc "Codemods & utilities for working with Phoenix"

  def add_scope(igniter, route, contents, opts \\ []) do
    {igniter, router} =
      case Keyword.fetch(opts, :router) do
        {:ok, router} ->
          {igniter, router}

        :error ->
          select_router(igniter)
      end

    scope_code =
      case Keyword.fetch(opts, :arg2) do
        {:ok, arg2} ->
          contents = Sourceror.parse_string!(contents)

          quote do
            scope unquote(route), unquote(arg2) do
              unquote(contents)
            end
          end
          |> Sourceror.to_string()

        _ ->
          """
          scope #{inspect(route)} do
            #{contents}
          end
          """
      end

    if router do
      Igniter.Code.Module.find_and_update_module!(igniter, router, fn zipper ->
        case move_to_scope_location(zipper) do
          {:ok, zipper, append_or_prepend} ->
            {:ok, Igniter.Code.Common.add_code(zipper, scope_code, append_or_prepend)}

          :error ->
            {:warning,
             Igniter.Util.Warning.formatted_warning(
               "Could not add a scope for #{inspect(route)} to your router. Please add it manually.",
               scope_code
             )}
        end
      end)
    else
      Igniter.add_warning(
        igniter,
        Igniter.Util.Warning.formatted_warning(
          "Could not add a scope for #{inspect(route)} to your router. Please add it manually.",
          scope_code
        )
      )
    end
  end

  def add_pipeline(igniter, name, contents, opts \\ []) do
    {igniter, router} =
      case Keyword.fetch(opts, :router) do
        {:ok, router} ->
          {igniter, router}

        :error ->
          select_router(igniter)
      end

    pipeline_code = """
    pipeline #{inspect(name)} do
      #{contents}
    end
    """

    if router do
      Igniter.Code.Module.find_and_update_module!(igniter, router, fn zipper ->
        Igniter.Code.Function.move_to_function_call(zipper, :pipeline, 2, fn zipper ->
          Igniter.Code.Function.argument_matches_predicate?(
            zipper,
            0,
            &Igniter.Code.Common.nodes_equal?(&1, name)
          )
        end)
        |> case do
          {:ok, _} ->
            {:warning,
             Igniter.Util.Warning.formatted_warning(
               "The #{name} pipeline already exists in the router. Attempting to add scope: ",
               pipeline_code
             )}

          _ ->
            case move_to_pipeline_location(zipper) do
              {:ok, zipper, append_or_prepend} ->
                {:ok, Igniter.Code.Common.add_code(zipper, pipeline_code, append_or_prepend)}

              :error ->
                {:warning,
                 Igniter.Util.Warning.formatted_warning(
                   "Could not add the #{name} pipline to your router. Please add it manually.",
                   pipeline_code
                 )}
            end
        end
      end)
    else
      Igniter.add_warning(
        igniter,
        Igniter.Util.Warning.formatted_warning(
          "Could not add the #{name} pipline to your router. Please add it manually.",
          pipeline_code
        )
      )
    end
  end

  def select_router(igniter, label \\ "Which router should be modified?") do
    case list_routers(igniter) do
      {igniter, []} ->
        {igniter, nil}

      {igniter, [router]} ->
        {igniter, router}

      {igniter, routers} ->
        {igniter, Owl.IO.select(routers, label: label, render_as: &inspect/1)}
    end
  end

  def list_routers(igniter) do
    Igniter.Code.Module.find_all_matching_modules(igniter, fn _mod, zipper ->
      router_name =
        Module.concat([to_string(Igniter.Code.Module.module_name_prefix()) <> "Web"])

      with :error <-
             Igniter.Code.Function.move_to_function_call(zipper, :use, 2, fn zipper ->
               Igniter.Code.Function.argument_matches_predicate?(
                 zipper,
                 0,
                 &Igniter.Code.Common.nodes_equal?(&1, router_name)
               ) &&
                 Igniter.Code.Function.argument_matches_predicate?(
                   zipper,
                   1,
                   &Igniter.Code.Common.nodes_equal?(&1, :router)
                 )
             end),
           :error <- Igniter.Code.Module.move_to_use(zipper, Phoenix.Router) do
        false
      else
        _ ->
          true
      end
    end)
  end

  defp move_to_pipeline_location(zipper) do
    with {:pipeline, :error} <-
           {:pipeline,
            Igniter.Code.Function.move_to_function_call_in_current_scope(zipper, :pipeline, 2)},
         :error <-
           Igniter.Code.Function.move_to_function_call_in_current_scope(zipper, :scope, [2, 3, 4]) do
      case Igniter.Code.Module.move_to_use(zipper, Phoenix.Router) do
        {:ok, zipper} -> {:ok, zipper, :after}
        :error -> :error
      end
    else
      {:pipeline, {:ok, zipper}} ->
        {:ok, zipper, :after}

      {:ok, zipper} ->
        {:ok, zipper, :before}
    end
  end

  defp move_to_scope_location(zipper) do
    with :error <-
           Igniter.Code.Function.move_to_function_call_in_current_scope(zipper, :scope, [2, 3, 4]),
         {:pipeline, :error} <- {:pipeline, last_pipeline(zipper)} do
      case Igniter.Code.Module.move_to_use(zipper, Phoenix.Router) do
        {:ok, zipper} -> {:ok, zipper, :after}
        :error -> :error
      end
    else
      {:ok, zipper} ->
        {:ok, zipper, :before}

      {:pipeline, {:ok, zipper}} ->
        {:ok, zipper, :after}
    end
  end

  defp last_pipeline(zipper) do
    case Igniter.Code.Function.move_to_function_call_in_current_scope(zipper, :pipeline, 2) do
      {:ok, zipper} ->
        with zipper when not is_nil(zipper) <- Sourceror.Zipper.right(zipper),
             {:ok, zipper} <- last_pipeline(zipper) do
          {:ok, zipper}
        else
          _ ->
            {:ok, zipper}
        end

      :error ->
        :error
    end
  end
end
