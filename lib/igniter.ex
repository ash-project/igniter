defmodule Igniter do
  @moduledoc """
  Igniter is a library for installing packages and generating code.
  """

  defstruct [:rewrite, issues: []]

  def new() do
    %__MODULE__{rewrite: Rewrite.new()}
  end

  def add_issue(igniter, issue) do
    %{igniter | issues: [issue | igniter.issues]}
  end

  def compose_task(igniter, task_name, argv) do
    if igniter.issues == [] do
      task_name
      |> Mix.Task.get()
      |> case do
        nil ->
          igniter

        task ->
          Code.ensure_compiled!(task)

          if function_exported?(task, :igniter, 2) do
            if !task.supports_umbrella?() && Mix.Project.umbrella?() do
              raise """
              Cannot run #{inspect(task)} in an umbrella project.
              """
            end

            task.igniter(igniter, argv)
          else
            add_issue(igniter, "#{inspect(task)} does not implement `Igniter.igniter/2`")
          end
      end
    else
      igniter
    end
  end

  def update_file(igniter, path, func) do
    if Rewrite.has_source?(igniter.rewrite, path) do
      %{igniter | rewrite: Rewrite.update!(igniter.rewrite, path, func)}
    else
      igniter
      |> include_existing_elixir_file(path)
      |> update_file(path, func)
    end
  end

  def include_existing_elixir_file(igniter, path) do
    if Rewrite.has_source?(igniter.rewrite, path) do
      igniter
    else
      if File.exists?(path) do
        %{igniter | rewrite: Rewrite.put!(igniter.rewrite, Rewrite.Source.Ex.read!(path))}
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
  end
end
