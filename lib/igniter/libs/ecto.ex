defmodule Igniter.Libs.Ecto do
  @moduledoc "Codemods & utilities for working with Ecto"

  @known_repos [
    Ecto.Repo,
    AshPostgres.Repo,
    AshSqlite.Repo,
    AshMysql.Repo
  ]

  @doc """
  Selects a repo module from the list of available repos.

  ## Options

  * `:label` - The label to display to the user when selecting the repo
  """
  @spec select_repo(Igniter.t(), Keyword.t()) :: {Igniter.t(), nil | module()}
  def select_repo(igniter, opts \\ []) do
    label = Keyword.get(opts, :label, "Which repo should be used?")

    case list_repos(igniter) do
      {igniter, []} ->
        {igniter, nil}

      {igniter, [repo]} ->
        {igniter, repo}

      {igniter, repos} ->
        {igniter, Igniter.Util.IO.select(label, repos, display: &inspect/1)}
    end
  end

  @doc "Lists all the ecto repos in the project"
  @spec list_repos(Igniter.t()) :: {Igniter.t(), [module()]}
  def list_repos(igniter) do
    Igniter.Project.Module.find_all_matching_modules(igniter, fn _mod, zipper ->
      move_to_repo_use(zipper) != :error
    end)
  end

  defp move_to_repo_use(zipper) do
    Igniter.Code.Function.move_to_function_call(zipper, :use, [1, 2], fn zipper ->
      Enum.any?(@known_repos, fn repo ->
        Igniter.Code.Function.argument_equals?(
          zipper,
          0,
          repo
        )
      end)
    end)
  end
end
