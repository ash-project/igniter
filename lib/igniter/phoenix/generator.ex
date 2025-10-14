# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule Igniter.Phoenix.Generator do
  @moduledoc false
  # Wrap Phx.New.Generator
  # https://github.com/phoenixframework/phoenix/blob/7586cbee9e37afbe0b3cdbd560b9e6aa60d32bf6/installer/lib/phx_new/generator.ex#L69

  def copy_from(igniter, project, mod, name) when is_atom(name) do
    mapping = mod.template_files(name)

    templates =
      for {format, _project_location, files} <- mapping,
          {source, target_path} <- files,
          source = to_string(source) do
        target = expand_path_with_bindings(target_path, project)
        {format, source, target}
      end

    Enum.reduce(templates, igniter, fn {format, source, target}, acc ->
      case format do
        :keep ->
          acc

        :text ->
          contents = mod.render(name, source, project.binding)
          Igniter.create_new_file(acc, target, contents, on_exists: :overwrite)

        :config ->
          contents = mod.render(name, source, project.binding)
          config_inject(acc, target, contents)

        :prod_config ->
          contents = mod.render(name, source, project.binding)
          prod_only_config_inject(acc, target, contents)

        :eex ->
          contents = mod.render(name, source, project.binding)
          Igniter.create_new_file(acc, target, contents, on_exists: :overwrite)
      end
    end)
  end

  defp expand_path_with_bindings(path, project) do
    Regex.replace(Regex.recompile!(~r/:[a-zA-Z0-9_]+/), path, fn ":" <> key, _ ->
      project |> Map.fetch!(:"#{key}") |> to_string()
    end)
  end

  defp config_inject(igniter, file, to_inject) do
    patterns = [
      """
      import Config
      __cursor__()
      """
    ]

    Igniter.create_or_update_elixir_file(igniter, file, to_inject, fn zipper ->
      case Igniter.Code.Common.move_to_cursor_match_in_scope(zipper, patterns) do
        {:ok, zipper} ->
          {:ok, Igniter.Code.Common.add_code(zipper, to_inject)}

        _ ->
          {:warning,
           """
           Could not automatically inject the following config into #{file}

           #{to_inject}
           """}
      end
    end)
  end

  defp prod_only_config_inject(igniter, file, to_inject) do
    patterns = [
      """
      if config_env() == :prod do
        __cursor__()
      end
      """,
      """
      if :prod == config_env() do
        __cursor__()
      end
      """
    ]

    Igniter.create_or_update_elixir_file(igniter, file, to_inject, fn zipper ->
      case Igniter.Code.Common.move_to_cursor_match_in_scope(zipper, patterns) do
        {:ok, zipper} ->
          {:ok, Igniter.Code.Common.add_code(zipper, to_inject)}

        _ ->
          {:warning,
           """
           Could not automatically inject the following config into #{file}

           #{to_inject}
           """}
      end
    end)
  end

  def gen_ecto_config(igniter, %{binding: binding}) do
    adapter_config = binding[:adapter_config]

    config_inject(igniter, "config/dev.exs", """
    # Configure your database
    config :#{binding[:app_name]}, #{binding[:app_module]}.Repo#{kw_to_config(adapter_config[:dev])}
    """)
  end

  defp kw_to_config(kw) do
    Enum.map(kw, fn
      {k, {:literal, v}} -> ",\n  #{k}: #{v}"
      {k, v} -> ",\n  #{k}: #{inspect(v)}"
    end)
  end
end
