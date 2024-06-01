defmodule Igniter do
  @moduledoc """
  Igniter is a library for installing packages and generating code.
  """

  defstruct [:rewrite, issues: [], tasks: []]

  @type t :: %__MODULE__{
          rewrite: Rewrite.t(),
          issues: [String.t()],
          tasks: [{String.t() | list(STring.t())}]
        }

  def new() do
    %__MODULE__{rewrite: Rewrite.new()}
  end

  def add_issue(igniter, issue) do
    %{igniter | issues: [issue | igniter.issues]}
  end

  def add_task(igniter, task, argv \\ []) when is_binary(task) do
    %{igniter | tasks: igniter.tasks ++ [{task, argv}]}
  end

  def compose_task(igniter, task, argv) when is_atom(task) do
    Code.ensure_compiled!(task)

    if function_exported?(task, :igniter, 2) do
      if !task.supports_umbrella?() && Mix.Project.umbrella?() do
        add_issue(igniter, "Cannot run #{inspect(task)} in an umbrella project.")
      else
        task.igniter(igniter, argv)
      end
    else
      add_issue(igniter, "#{inspect(task)} does not implement `Igniter.igniter/2`")
    end
  end

  def compose_task(igniter, task_name, argv) do
    if igniter.issues == [] do
      task_name
      |> Mix.Task.get()
      |> case do
        nil ->
          igniter

        task ->
          compose_task(igniter, task, argv)
      end
    else
      igniter
    end
  end

  def update_file(igniter, path, func) do
    if Rewrite.has_source?(igniter.rewrite, path) do
      %{igniter | rewrite: Rewrite.update!(igniter.rewrite, path, func)}
    else
      if File.exists?(path) do
        source = Rewrite.Source.Ex.read!(path)

        %{igniter | rewrite: Rewrite.put!(igniter.rewrite, source)}
        |> format(path)
        |> Map.update!(:rewrite, fn rewrite ->
          source = Rewrite.source!(rewrite, path)
          Rewrite.update!(rewrite, path, func.(source))
        end)
      else
        add_issue(igniter, "Required #{path} but it did not exist")
      end
    end
  end

  def include_existing_elixir_file(igniter, path) do
    if Rewrite.has_source?(igniter.rewrite, path) do
      igniter
    else
      if File.exists?(path) do
        %{igniter | rewrite: Rewrite.put!(igniter.rewrite, Rewrite.Source.Ex.read!(path))}
        |> format(path)
      else
        add_issue(igniter, "Required #{path} but it did not exist")
      end
    end
  end

  def include_or_create_elixir_file(igniter, path, contents \\ "") do
    if Rewrite.has_source?(igniter.rewrite, path) do
      igniter
    else
      source =
        try do
          Rewrite.Source.Ex.read!(path)
        rescue
          _ ->
            ""
            |> Rewrite.Source.Ex.from_string(path)
            |> Rewrite.Source.update(:file_creator, :content, contents)
        end

      %{igniter | rewrite: Rewrite.put!(igniter.rewrite, source)}
      |> format(path)
    end
  end

  def create_new_elixir_file(igniter, path, contents \\ "") do
    source =
      try do
        path
        |> Rewrite.Source.Ex.read!()
        |> Rewrite.Source.add_issue("File already exists")
      rescue
        _ ->
          ""
          |> Rewrite.Source.Ex.from_string(path)
          |> Rewrite.Source.update(:file_creator, :content, contents)
      end

    %{igniter | rewrite: Rewrite.put!(igniter.rewrite, source)}
    |> format(path)
  end

  defp format(igniter, adding_path \\ nil) do
    if adding_path && Path.basename(adding_path) == ".formatter.exs" do
      format(igniter)
    else
      igniter =
        "**/.formatter.exs"
        |> Path.relative_to(File.cwd!())
        |> Path.wildcard()
        |> Enum.reduce(igniter, fn path, igniter ->
          Igniter.include_existing_elixir_file(igniter, path)
        end)

      rewrite = igniter.rewrite

      formatter_exs_files =
        rewrite
        |> Enum.filter(fn source ->
          source
          |> Rewrite.Source.get(:path)
          |> Path.basename()
          |> Kernel.==(".formatter.exs")
        end)
        |> Map.new(fn source ->
          dir =
            source
            |> Rewrite.Source.get(:path)
            |> Path.dirname()

          {dir, source}
        end)

      rewrite =
        Rewrite.map!(rewrite, fn source ->
          path = source |> Rewrite.Source.get(:path)

          if is_nil(adding_path) || path == adding_path do
            dir = Path.dirname(path)

            case find_formatter_exs_file_options(dir, formatter_exs_files) do
              :error ->
                source

              {:ok, opts} ->
                formatted = Rewrite.Source.Ex.format(source, opts)

                source
                |> Rewrite.Source.Ex.put_formatter_opts(opts)
                |> Rewrite.Source.update(:content, formatted)
            end
          else
            source
          end
        end)

      %{igniter | rewrite: rewrite}
    end
  end

  defp find_formatter_exs_file_options(path, formatter_exs_files) do
    case Map.fetch(formatter_exs_files, path) do
      {:ok, source} ->
        {opts, _} = Rewrite.Source.get(source, :quoted) |> Code.eval_quoted()

        {:ok, eval_deps(opts)}

      :error ->
        if path in ["/", "."] do
          :error
        else
          new_path =
            Path.join(path, "..")
            |> Path.expand()
            |> Path.relative_to_cwd()

          find_formatter_exs_file_options(new_path, formatter_exs_files)
        end
    end
  end

  # This can be removed if/when this PR is merged: https://github.com/hrzndhrn/rewrite/pull/34
  defp eval_deps(formatter_opts) do
    deps = Keyword.get(formatter_opts, :import_deps, [])

    locals_without_parens = eval_deps_opts(deps)

    formatter_opts =
      Keyword.update(
        formatter_opts,
        :locals_without_parens,
        locals_without_parens,
        &(locals_without_parens ++ &1)
      )

    formatter_opts
  end

  defp eval_deps_opts([]) do
    []
  end

  defp eval_deps_opts(deps) do
    deps_paths = Mix.Project.deps_paths()

    for dep <- deps,
        dep_path = fetch_valid_dep_path(dep, deps_paths),
        !is_nil(dep_path),
        dep_dot_formatter = Path.join(dep_path, ".formatter.exs"),
        File.regular?(dep_dot_formatter),
        dep_opts = eval_file_with_keyword_list(dep_dot_formatter),
        parenless_call <- dep_opts[:export][:locals_without_parens] || [],
        uniq: true,
        do: parenless_call
  end

  defp fetch_valid_dep_path(dep, deps_paths) when is_atom(dep) do
    with %{^dep => path} <- deps_paths,
         true <- File.dir?(path) do
      path
    else
      _ ->
        nil
    end
  end

  defp fetch_valid_dep_path(_dep, _deps_paths) do
    nil
  end

  defp eval_file_with_keyword_list(path) do
    {opts, _} = Code.eval_file(path)

    unless Keyword.keyword?(opts) do
      raise "Expected #{inspect(path)} to return a keyword list, got: #{inspect(opts)}"
    end

    opts
  end
end
