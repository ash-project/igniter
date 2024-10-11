defmodule Mix.Tasks.Igniter.UpdateGettext do
  use Igniter.Mix.Task

  @shortdoc "Applies changes to resolve a warning introduced in gettext 0.26.0"
  @moduledoc """
  #{@shortdoc}
  """

  def info(_argv, _source) do
    %Igniter.Mix.Task.Info{group: :igniter}
  end

  def igniter(igniter, _argv) do
    {igniter, modules} = find_use_gettext_modules(igniter)

    modules
    |> Enum.reduce(igniter, fn module, igniter ->
      igniter
      |> use_gettext_backend(module)
      |> rewrite_imports(module)
    end)
    |> Igniter.Project.Deps.add_dep(
      {:gettext, "~> 0.26 and >= 0.26.1"},
      yes?: true
    )
  end

  defp rewrite_imports(igniter, rewriting_module) do
    {igniter, modules} =
      Igniter.Project.Module.find_all_matching_modules(igniter, fn _module, zipper ->
        match?(
          {:ok, _},
          Igniter.Code.Common.move_to(zipper, fn zipper ->
            import?(zipper, rewriting_module)
          end)
        )
      end)

    Enum.reduce(modules, igniter, fn module, igniter ->
      Igniter.Project.Module.find_and_update_module!(igniter, module, fn zipper ->
        Igniter.Code.Common.update_all_matches(zipper, &import?(&1, rewriting_module), fn _ ->
          {:code,
           quote do
             use Gettext, backend: unquote(rewriting_module)
           end}
        end)
      end)
    end)
  end

  defp find_use_gettext_modules(igniter) do
    Igniter.Project.Module.find_all_matching_modules(igniter, fn _module, zipper ->
      case Igniter.Code.Module.move_to_use(zipper, Gettext) do
        {:ok, _zipper} -> true
        _ -> false
      end
    end)
  end

  defp import?(zipper, module) do
    Igniter.Code.Function.function_call?(zipper, :import, 1) &&
      Igniter.Code.Function.argument_equals?(zipper, 0, module)
  end

  defp use_gettext_backend(igniter, module) do
    Igniter.Project.Module.find_and_update_module!(igniter, module, fn zipper ->
      with {:ok, zipper} <- Igniter.Code.Module.move_to_use(zipper, Gettext),
           {:ok, zipper} <-
             Igniter.Code.Function.update_nth_argument(zipper, 0, fn zipper ->
               {:ok, Igniter.Code.Common.replace_code(zipper, Gettext.Backend)}
             end) do
        {:ok, zipper}
      else
        _ ->
          {:warning, "Failed to update to Gettext.Backend in #{inspect(module)}"}
      end
    end)
  end
end
