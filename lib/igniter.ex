defmodule Igniter do
  @moduledoc """
  Tools for generating and patching code into an Elixir project.
  """

  defstruct [:rewrite, issues: [], tasks: [], warnings: [], assigns: %{}]

  alias Sourceror.Zipper

  @type t :: %__MODULE__{
          rewrite: Rewrite.t(),
          issues: [String.t()],
          tasks: [{String.t() | list(String.t())}],
          warnings: [String.t()],
          assigns: map()
        }

  @type zipper_updater :: (Zipper.t() -> {:ok, Zipper.t()} | {:error, String.t() | [String.t()]})

  @doc "Returns a new igniter"
  @spec new() :: t()
  def new do
    %__MODULE__{rewrite: Rewrite.new()}
  end

  @doc "Stores the key/value pair in `igniter.assigns`"
  @spec assign(t, atom, term()) :: t()
  def assign(igniter, key, value) do
    %{igniter | assigns: Map.put(igniter.assigns, key, value)}
  end

  def assign(igniter, key_vals) do
    Enum.reduce(key_vals, igniter, fn {key, value}, igniter ->
      assign(igniter, key, value)
    end)
  end

  @doc "Includes all files matching the given glob, expecting them all (for now) to be elixir files."
  @spec include_glob(t, Path.t() | GlobEx.t()) :: t()
  def include_glob(igniter, glob) do
    glob
    |> case do
      %GlobEx{} = glob -> glob
      string -> GlobEx.compile!(string)
    end
    |> GlobEx.ls()
    |> Enum.reduce(igniter, fn path, igniter ->
      if Path.extname(path) in [".ex", ".exs"] do
        Igniter.include_existing_elixir_file(igniter, path)
      else
        raise ArgumentError,
              "Cannot include #{inspect(path)} because it is not an Elixir file. This can be supported in the future, but the work hasn't been done yet."
      end
    end)
  end

  @doc """
  Updates all files matching the given glob with the given zipper function.

  Adds any new files matching that glob to the igniter first.
  """
  @spec update_glob(
          t,
          Path.t() | GlobEx.t(),
          zipper_updater
        ) :: t()
  def update_glob(igniter, glob, func) do
    glob =
      case glob do
        %GlobEx{} = glob -> glob
        string -> GlobEx.compile!(string)
      end

    igniter = include_glob(igniter, glob)

    Enum.reduce(igniter.rewrite, igniter, fn source, igniter ->
      path = Rewrite.Source.get(source, :path)

      if GlobEx.match?(glob, path) do
        update_elixir_file(igniter, path, func)
      else
        igniter
      end
    end)
  end

  @doc "Adds an issue to the issues list. Any issues will prevent writing and be displayed to the user."
  @spec add_issue(t, term | list(term)) :: t()
  def add_issue(igniter, issue) do
    %{igniter | issues: List.wrap(issue) ++ igniter.issues}
  end

  @doc "Adds a warning to the warnings list. Warnings will not prevent writing, but will be displayed to the user."
  @spec add_warning(t, term | list(term)) :: t()
  def add_warning(igniter, warning) do
    %{igniter | warnings: List.wrap(warning) ++ igniter.warnings}
  end

  @doc "Adds a task to the tasks list. Tasks will be run after all changes have been commited"
  def add_task(igniter, task, argv \\ []) when is_binary(task) do
    %{igniter | tasks: igniter.tasks ++ [{task, argv}]}
  end

  @doc "Finds the `Igniter.Mix.Task` task by name and composes it (calls its `igniter/2`) into the current igniter."
  def compose_task(igniter, task, argv \\ [])

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

  @doc """
  Updates the source code of the given elixir file
  """
  @spec update_elixir_file(t(), Path.t(), zipper_updater()) :: Igniter.t()
  def update_elixir_file(igniter, path, func) do
    if Rewrite.has_source?(igniter.rewrite, path) do
      source = Rewrite.source!(igniter.rewrite, path)

      igniter
      |> apply_func_with_zipper(source, func)
      |> format(path)
    else
      if File.exists?(path) do
        source = Rewrite.Source.Ex.read!(path)

        %{igniter | rewrite: Rewrite.put!(igniter.rewrite, source)}
        |> format(path)
        |> apply_func_with_zipper(source, func)
      else
        add_issue(igniter, "Required #{path} but it did not exist")
      end
    end
  end

  @doc """
  Updates a given file's `Rewrite.Source`
  """
  @spec update_file(t(), Path.t(), (Rewrite.Source.t() -> Rewrite.Source.t())) :: t()
  def update_file(igniter, path, updater) do
    if Rewrite.has_source?(igniter.rewrite, path) do
      %{igniter | rewrite: Rewrite.update!(igniter.rewrite, path, updater)}
    else
      if File.exists?(path) do
        source = Rewrite.Source.Ex.read!(path)

        %{igniter | rewrite: Rewrite.put!(igniter.rewrite, source)}
        |> format(path)
        |> Map.update!(:rewrite, fn rewrite ->
          source = Rewrite.source!(rewrite, path)
          Rewrite.update!(rewrite, path, updater.(source))
        end)
      else
        add_issue(igniter, "Required #{path} but it did not exist")
      end
    end
  end

  @doc "Includes the given file in the project, expecting it to exist. Does nothing if its already been added."
  @spec include_existing_elixir_file(t(), Path.t()) :: t()
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

  @doc "Includes or creates the given file in the project with the provided contents. Does nothing if its already been added."
  @spec include_or_create_elixir_file(t(), Path.t(), contents :: String.t()) :: t()
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

  @spec exists?(t(), Path.t()) :: boolean()
  def exists?(igniter, path) do
    Rewrite.has_source?(igniter.rewrite, path) || File.exists?(path)
  end

  @doc "Creates the given file in the project with the provided string contents, or updates it with a function of type `zipper_updater()` if it already exists."
  @spec create_or_update_elixir_file(t(), Path.t(), String.t(), zipper_updater()) :: Igniter.t()
  def create_or_update_elixir_file(igniter, path, contents, updater) do
    if Rewrite.has_source?(igniter.rewrite, path) do
      igniter
      |> update_elixir_file(path, updater)
    else
      {created?, source} =
        try do
          {false, Rewrite.Source.Ex.read!(path)}
        rescue
          _ ->
            {true,
             ""
             |> Rewrite.Source.Ex.from_string(path)
             |> Rewrite.Source.update(:file_creator, :content, contents)}
        end

      %{igniter | rewrite: Rewrite.put!(igniter.rewrite, source)}
      |> format(path)
      |> then(fn igniter ->
        if created? do
          igniter
        else
          update_elixir_file(igniter, path, updater)
        end
      end)
    end
  end

  @doc "Creates a new elixir file in the project with the provided string contents. Adds an error if it already exists."
  @spec create_new_elixir_file(t(), Path.t(), String.t()) :: Igniter.t()
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

  @doc """
  Executes or dry-runs a given Igniter.

  This takes `argv` to parameterize it as it is generally invoked from a mix task.
  """
  def do_or_dry_run(igniter, argv, opts \\ []) do
    igniter = %{igniter | issues: Enum.uniq(igniter.issues)}
    title = opts[:title] || "Igniter"

    sources =
      igniter.rewrite
      |> Rewrite.sources()

    issues =
      Enum.flat_map(sources, fn source ->
        changed_issues =
          if Rewrite.Source.file_changed?(source) do
            ["File has been changed since it was originally read."]
          else
            []
          end

        issues = Enum.uniq(changed_issues ++ Rewrite.Source.issues(source))

        case issues do
          [] -> []
          issues -> [{source, issues}]
        end
      end)

    case issues do
      [_ | _] ->
        explain_issues(issues)

        :issues

      [] ->
        case igniter do
          %{issues: []} ->
            result_of_dry_run =
              sources
              |> Enum.filter(fn source ->
                Rewrite.Source.updated?(source)
              end)
              |> case do
                [] ->
                  unless opts[:quiet_on_no_changes?] || "--yes" in argv do
                    Mix.shell().info("\n#{title}: No proposed changes!\n")
                  end

                  :dry_run_with_no_changes

                sources ->
                  if "--dry-run" in argv || "--yes" not in argv do
                    Mix.shell().info("\n#{title}: Proposed changes:\n")

                    Enum.each(sources, fn source ->
                      if Rewrite.Source.from?(source, :string) do
                        content_lines =
                          source
                          |> Rewrite.Source.get(:content)
                          |> String.split("\n")
                          |> Enum.with_index()

                        space_padding =
                          content_lines
                          |> Enum.map(&elem(&1, 1))
                          |> Enum.max()
                          |> to_string()
                          |> String.length()

                        diffish_looking_text =
                          Enum.map_join(content_lines, "\n", fn {line, line_number_minus_one} ->
                            line_number = line_number_minus_one + 1

                            "#{String.pad_trailing(to_string(line_number), space_padding)} #{IO.ANSI.yellow()}| #{IO.ANSI.green()}#{line}#{IO.ANSI.reset()}"
                          end)

                        Mix.shell().info("""
                        Create: #{Rewrite.Source.get(source, :path)}

                        #{diffish_looking_text}
                        """)
                      else
                        Mix.shell().info("""
                        Update: #{Rewrite.Source.get(source, :path)}

                        #{Rewrite.Source.diff(source)}
                        """)
                      end
                    end)
                  end

                  :dry_run_with_changes
              end

            if igniter.warnings != [] do
              Mix.shell().info("\n#{title} - #{IO.ANSI.yellow()}Notices:#{IO.ANSI.reset()}\n")

              igniter.warnings
              |> Enum.map_join("\n --- \n", fn error ->
                if is_binary(error) do
                  "* #{IO.ANSI.yellow()}#{error}#{IO.ANSI.reset()}"
                else
                  "* #{IO.ANSI.yellow()}#{Exception.format(:error, error)}#{IO.ANSI.reset()}"
                end
              end)
              |> Mix.shell().info()
            end

            if igniter.tasks != [] do
              message =
                if result_of_dry_run == :dry_run_with_no_changes do
                  "The following tasks will be run"
                else
                  "The following tasks will be run after the above changes:"
                end

              Mix.shell().info("""
              #{message}

              #{Enum.map_join(igniter.tasks, "\n", fn {task, args} -> "* #{IO.ANSI.red()}#{task}#{IO.ANSI.yellow()} #{Enum.join(args, " ")}#{IO.ANSI.reset()}" end)}
              """)
            end

            if "--dry-run" in argv || result_of_dry_run == :dry_run_with_no_changes do
              result_of_dry_run
            else
              if "--yes" in argv ||
                   Mix.shell().yes?(opts[:confirmation_message] || "Proceed with changes?") do
                sources
                |> Enum.any?(fn source ->
                  Rewrite.Source.updated?(source)
                end)
                |> if do
                  igniter.rewrite
                  |> Rewrite.write_all()
                  |> case do
                    {:ok, _result} ->
                      igniter.tasks
                      |> Enum.each(fn {task, args} ->
                        Mix.shell().cmd("mix #{task} #{Enum.join(args, " ")}")
                      end)

                      :changes_made

                    {:error, error, rewrite} ->
                      igniter
                      |> Map.put(:rewrite, rewrite)
                      |> Igniter.add_issue(error)
                      |> igniter_issues()

                      :issues
                  end
                else
                  :no_changes
                end
              else
                :changes_aborted
              end
            end

          igniter ->
            igniter_issues(igniter)
            :issues
        end
    end
  end

  defp igniter_issues(igniter) do
    Mix.shell().info("Issues during code generation")

    igniter.issues
    |> Enum.map_join("\n", fn error ->
      if is_binary(error) do
        "* #{error}"
      else
        "* #{Exception.format(:error, error)}"
      end
    end)
    |> Mix.shell().info()
  end

  defp explain_issues(issues) do
    Mix.shell().info("Igniter: Issues found in proposed changes:\n")

    Enum.each(issues, fn {source, issues} ->
      Mix.shell().info("Issues with #{Rewrite.Source.get(source, :path)}")

      issues
      |> Enum.map_join("\n", fn error ->
        if is_binary(error) do
          "* #{error}"
        else
          "* #{Exception.format(:error, error)}"
        end
      end)
      |> Mix.shell().error()
    end)
  end

  defp format(igniter, adding_path \\ nil) do
    igniter = include_glob(igniter, "config/{config,#{Mix.env()}}.exs")

    if adding_path && Path.basename(adding_path) == ".formatter.exs" do
      format(igniter)
    else
      igniter =
        "**/.formatter.exs"
        |> Path.wildcard()
        |> Enum.reduce(igniter, fn path, igniter ->
          Igniter.include_existing_elixir_file(igniter, path)
        end)

      igniter =
        if File.exists?(".formatter.exs") do
          Igniter.include_existing_elixir_file(igniter, ".formatter.exs")
        else
          igniter
        end

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

            opts =
              case find_formatter_exs_file_options(dir, formatter_exs_files, Path.extname(path)) do
                :error ->
                  []

                {:ok, opts} ->
                  opts
              end

            formatted =
              with_evaled_configs(rewrite, fn ->
                Rewrite.Source.Ex.format(source, opts)
              end)

            source
            |> Rewrite.Source.Ex.put_formatter_opts(opts)
            |> Rewrite.Source.update(:content, formatted)
          else
            source
          end
        end)

      %{igniter | rewrite: rewrite}
    end
  end

  # for now we only eval `config.exs`
  defp with_evaled_configs(rewrite, fun) do
    [
      Rewrite.source(rewrite, "config/config.exs"),
      Rewrite.source(rewrite, "config/#{Mix.env()}.exs")
    ]
    |> Enum.flat_map(fn
      {:ok, source} ->
        [Rewrite.Source.get(source, :content)]

      _ ->
        []
    end)
    |> case do
      [] ->
        fun.()

      contents ->
        to_set =
          contents
          |> Enum.join("\n")
          |> String.split("import_config", parts: 2)
          |> List.first()
          |> then(&Config.Reader.eval!("config/config.exs", &1, env: Mix.env()))

        restore =
          to_set
          |> Keyword.keys()
          |> Enum.map(fn key ->
            {key, Application.get_all_env(key)}
          end)

        try do
          Application.put_all_env(to_set)

          fun.()
        after
          Application.put_all_env(restore)
        end
    end
  end

  # sobelow_skip ["RCE.CodeModule"]
  defp find_formatter_exs_file_options(path, formatter_exs_files, ext) do
    case Map.fetch(formatter_exs_files, path) do
      {:ok, source} ->
        {opts, _} = Rewrite.Source.get(source, :quoted) |> Code.eval_quoted()

        {:ok, opts |> eval_deps() |> filter_plugins(ext)}

      :error ->
        if path in ["/", "."] do
          :error
        else
          new_path =
            Path.join(path, "..")
            |> Path.expand()
            |> Path.relative_to_cwd()

          find_formatter_exs_file_options(new_path, formatter_exs_files, ext)
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

  # sobelow_skip ["RCE.CodeModule"]
  defp eval_file_with_keyword_list(path) do
    {opts, _} = Code.eval_file(path)

    unless Keyword.keyword?(opts) do
      raise "Expected #{inspect(path)} to return a keyword list, got: #{inspect(opts)}"
    end

    opts
  end

  defp apply_func_with_zipper(igniter, source, func) do
    quoted = Rewrite.Source.get(source, :quoted)
    zipper = Sourceror.Zipper.zip(quoted)

    case func.(zipper) do
      {:ok, %Sourceror.Zipper{} = zipper} ->
        Rewrite.update!(
          igniter.rewrite,
          Rewrite.Source.update(
            source,
            :configure,
            :quoted,
            Sourceror.Zipper.root(zipper)
          )
        )
        |> then(&Map.put(igniter, :rewrite, &1))

      %Sourceror.Zipper{} = zipper ->
        Rewrite.update!(
          igniter.rewrite,
          Rewrite.Source.update(
            source,
            :configure,
            :quoted,
            Sourceror.Zipper.root(zipper)
          )
        )
        |> then(&Map.put(igniter, :rewrite, &1))

      {:error, error} ->
        Rewrite.update!(
          igniter.rewrite,
          Rewrite.Source.add_issues(source, List.wrap(error))
        )
        |> then(&Map.put(igniter, :rewrite, &1))

      {:warning, warning} ->
        Igniter.add_warning(igniter, warning)
    end
  end

  defp filter_plugins(opts, ext) do
    Keyword.put(opts, :plugins, plugins_for_ext(opts, ext))
  end

  defp plugins_for_ext(formatter_opts, ext) do
    formatter_opts
    |> Keyword.get(:plugins, [])
    |> Enum.filter(fn plugin ->
      Code.ensure_loaded?(plugin) and function_exported?(plugin, :features, 1) and
        ext in List.wrap(plugin.features(formatter_opts)[:extensions])
    end)
  end
end
