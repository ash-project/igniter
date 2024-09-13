defmodule Igniter.Libs.Phoenix do
  @moduledoc "Codemods & utilities for working with Phoenix"

  @doc """
  Returns the web module name for the current app
  """
  @spec web_module_name() :: module()
  @deprecated "Use `web_module/0` instead."
  def web_module_name do
    Module.concat([inspect(Igniter.Code.Module.module_name_prefix(Igniter.new())) <> "Web"])
  end

  @doc """
  Returns the web module name for the current app
  """
  @spec web_module(Igniter.t()) :: module()
  def web_module(igniter) do
    Module.concat([inspect(Igniter.Code.Module.module_name_prefix(igniter)) <> "Web"])
  end

  @spec html?(Igniter.t(), module()) :: boolean()
  def html?(igniter, module) do
    zipper = elem(Igniter.Code.Module.find_module!(igniter, module), 2)

    case Igniter.Code.Common.move_to(zipper, fn zipper ->
           if Igniter.Code.Function.function_call?(zipper, :use, 2) do
             using_a_webbish_module?(zipper) &&
               Igniter.Code.Function.argument_equals?(zipper, 1, :html)
           else
             false
           end
         end) do
      {:ok, _} ->
        true

      _ ->
        false
    end
  end

  @spec controller?(Igniter.t(), module()) :: boolean()
  def controller?(igniter, module) do
    zipper = elem(Igniter.Code.Module.find_module!(igniter, module), 2)

    case Igniter.Code.Common.move_to(zipper, fn zipper ->
           if Igniter.Code.Function.function_call?(zipper, :use, 2) do
             using_a_webbish_module?(zipper) &&
               Igniter.Code.Function.argument_equals?(zipper, 1, :controller)
           else
             false
           end
         end) do
      {:ok, _} ->
        true

      _ ->
        false
    end
  end

  defp using_a_webbish_module?(zipper) do
    case Igniter.Code.Function.move_to_nth_argument(zipper, 0) do
      {:ok, zipper} ->
        Igniter.Code.Module.module_matching?(zipper, &String.ends_with?(to_string(&1), "Web"))

      :error ->
        false
    end
  end

  @doc """
  Generates a module name that lives in the Web directory of the current app.
  """
  @spec web_module_name(String.t()) :: module()
  @deprecated "Use `web_module_name/1` instead."
  def web_module_name(suffix) do
    Module.concat(inspect(Igniter.Code.Module.module_name_prefix(Igniter.new())) <> "Web", suffix)
  end

  @spec web_module_name(Igniter.t(), String.t()) :: module()
  def web_module_name(igniter, suffix) do
    Module.concat(inspect(Igniter.Code.Module.module_name_prefix(igniter)) <> "Web", suffix)
  end

  @spec endpoints_for_router(igniter :: Igniter.t(), router :: module()) ::
          {Igniter.t(), list(module())}
  def endpoints_for_router(igniter, router) do
    Igniter.Code.Module.find_all_matching_modules(igniter, fn _module, zipper ->
      with {:ok, _} <- Igniter.Code.Module.move_to_use(zipper, Phoenix.Endpoint),
           {:ok, _} <-
             Igniter.Code.Function.move_to_function_call_in_current_scope(
               zipper,
               :plug,
               [1, 2],
               &Igniter.Code.Function.argument_equals?(&1, 0, router)
             ) do
        true
      else
        _ ->
          false
      end
    end)
  end

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
        case move_to_scope_location(igniter, zipper) do
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
            if Keyword.get(opts, :warn_on_present?, true) do
              {:warning,
               Igniter.Util.Warning.formatted_warning(
                 "The #{name} pipeline already exists in the router. Attempting to add scope: ",
                 pipeline_code
               )}
            else
              {:ok, zipper}
            end

          _ ->
            case move_to_pipeline_location(igniter, zipper) do
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
        router_numbers =
          routers
          |> Enum.with_index()
          |> Enum.map_join("\n", fn {router, index} ->
            "#{index}. #{inspect(router)}"
          end)

        case String.trim(
               Mix.shell().prompt(label <> "\n" <> router_numbers <> "\nInput router number ❯ ")
             ) do
          "" ->
            select_router(igniter, label)

          router ->
            case Integer.parse(router) do
              {int, ""} ->
                {igniter, Enum.at(routers, int)}

              _ ->
                Mix.shell().info("Expected a number, got: #{router}")
                select_router(igniter, label)
            end
        end
    end
  end

  def list_routers(igniter) do
    Igniter.Code.Module.find_all_matching_modules(igniter, fn _mod, zipper ->
      move_to_router_use(igniter, zipper) != :error
    end)
  end

  defp move_to_router_use(igniter, zipper) do
    with :error <-
           Igniter.Code.Function.move_to_function_call(zipper, :use, 2, fn zipper ->
             Igniter.Code.Function.argument_matches_predicate?(
               zipper,
               0,
               &Igniter.Code.Common.nodes_equal?(&1, router_using(igniter))
             ) &&
               Igniter.Code.Function.argument_matches_predicate?(
                 zipper,
                 1,
                 &Igniter.Code.Common.nodes_equal?(&1, :router)
               )
           end) do
      Igniter.Code.Module.move_to_use(zipper, Phoenix.Router)
    end
  end

  defp move_to_pipeline_location(igniter, zipper) do
    with {:pipeline, :error} <-
           {:pipeline,
            Igniter.Code.Function.move_to_function_call_in_current_scope(zipper, :pipeline, 2)},
         :error <-
           Igniter.Code.Function.move_to_function_call_in_current_scope(zipper, :scope, [2, 3, 4]) do
      case move_to_router_use(igniter, zipper) do
        {:ok, zipper} -> {:ok, zipper, :after}
        :error -> :error
      end
    else
      {:pipeline, {:ok, zipper}} ->
        {:ok, zipper, :before}

      {:ok, zipper} ->
        {:ok, zipper, :before}
    end
  end

  defp move_to_scope_location(igniter, zipper) do
    with :error <-
           Igniter.Code.Function.move_to_function_call_in_current_scope(zipper, :scope, [2, 3, 4]),
         {:pipeline, :error} <- {:pipeline, last_pipeline(zipper)} do
      case move_to_router_use(igniter, zipper) do
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

  defp router_using(igniter) do
    Module.concat([to_string(Igniter.Code.Module.module_name_prefix(igniter)) <> "Web"])
  end
end
