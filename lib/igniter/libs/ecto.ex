defmodule Igniter.Libs.Ecto do
  @moduledoc "Codemods & utilities for working with Ecto"

  import Macro, only: [camelize: 1, underscore: 1]

  @known_repos [
    Ecto.Repo,
    AshPostgres.Repo,
    AshSqlite.Repo,
    AshMysql.Repo
  ]

  @doc """
  Generates a new migration file for the given repo.

  ## Options

  - `:body` - the body of the migration
  - `:timestamp` - the timestamp to use for the migration.
     Primarily useful for testing so you know what the filename will be.
  - `:on_exists` - what to do if the migration *module* already exists. Options are:
    - `:increment` - Calls this function again, but with an increasing number at the end, until it finds a free name. (default)
    - `:skip` - do nothing
    - `:overwrite` - overwrites the file
    - `{:error, error}` - adds an issue to the igniter that prevents writing and displays to the user
    - `{:warning, warning}` - adds a warning to the igniter that allows writing but displays to the user
  """
  @spec gen_migration(Igniter.t(), repo :: module(), name :: String.t(), opts :: Keyword.t()) ::
          Igniter.t()
  def gen_migration(igniter, repo, name, opts \\ []) do
    # getting the repos configuration will be a bit harder here
    # we'd need to look in config files or in the repos init or in the repo function?
    # not worth it for now
    path =
      Path.join(
        "priv/#{repo |> Module.split() |> List.last() |> Macro.underscore()}",
        "migrations"
      )

    base_name = "#{underscore(name)}.exs"
    file = Path.join(path, "#{opts[:timestamp] || timestamp()}_#{base_name}")

    igniter = Igniter.include_glob(igniter, Path.join(path, "**/*.exs"))

    body =
      opts[:body] ||
        """
        def change do
          # your migration here
        end
        """

    module = Module.concat([repo, Migrations, camelize(name)])

    case Igniter.Project.Module.module_exists(igniter, module) do
      {true, igniter} ->
        case Keyword.get(opts, :on_exists, :increment) do
          :skip ->
            igniter

          :increment ->
            name
            |> String.split("_", trim: true)
            |> List.last()
            |> Integer.parse()
            |> case do
              {integer, ""} when is_integer(integer) ->
                gen_migration(igniter, repo, name <> "_#{integer + 1}", opts)

              _ ->
                gen_migration(igniter, repo, name <> "_1", opts)
            end

          :ovewrwrite ->
            Igniter.create_new_file(
              igniter,
              file,
              """
              defmodule #{inspect(module)} do
                use Ecto.Migration

                #{body}
              end
              """,
              on_exists: :overwrite
            )

          {:error, error} ->
            Igniter.add_issue(igniter, error)

          {:warning, error} ->
            Igniter.add_warning(igniter, error)
        end

      {false, igniter} ->
        Igniter.create_new_file(igniter, file, """
        defmodule #{inspect(module)} do
          use Ecto.Migration

          #{body}
        end
        """)
    end
  end

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

  defp timestamp do
    {{y, m, d}, {hh, mm, ss}} = :calendar.universal_time()
    "#{y}#{pad(m)}#{pad(d)}#{pad(hh)}#{pad(mm)}#{pad(ss)}"
  end

  defp pad(i) when i < 10, do: <<?0, ?0 + i>>
  defp pad(i), do: to_string(i)
end
