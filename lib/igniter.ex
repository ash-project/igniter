defmodule Igniter do
  @moduledoc """
  Tools for generating and patching code into an Elixir project.
  """

  defstruct [:rewrite, issues: [], tasks: [], warnings: [], notices: [], assigns: %{}, moves: %{}]

  alias Sourceror.Zipper

  @type t :: %__MODULE__{
          rewrite: Rewrite.t(),
          issues: [String.t()],
          tasks: [String.t() | {String.t(), list(String.t())}],
          warnings: [String.t()],
          notices: [String.t()],
          assigns: map(),
          moves: %{optional(String.t()) => String.t()}
        }

  @type zipper_updater :: (Zipper.t() -> {:ok, Zipper.t()} | {:error, String.t() | [String.t()]})

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(igniter, opts) do
      rewrite =
        concat(
          "rewrite: ",
          container_doc(
            "#Rewrite<",
            [
              "#{Enum.count(igniter.rewrite.sources)} source(s)"
            ],
            ">",
            opts,
            fn str, _ -> str end
          )
        )

      issues =
        if Enum.empty?(igniter.issues) do
          empty()
        else
          concat("issues: ", to_doc(igniter.issues, opts))
        end

      warnings =
        if Enum.empty?(igniter.warnings) do
          empty()
        else
          concat("warnings: ", to_doc(igniter.warnings, opts))
        end

      notices =
        if Enum.empty?(igniter.notices) do
          empty()
        else
          concat("notices: ", to_doc(igniter.notices, opts))
        end

      tasks =
        if Enum.empty?(igniter.tasks) do
          empty()
        else
          concat("tasks: ", to_doc(igniter.tasks, opts))
        end

      moves =
        if Enum.empty?(igniter.moves) do
          empty()
        else
          concat("moves: ", to_doc(igniter.moves, opts))
        end

      container_doc(
        "#Igniter<",
        [
          rewrite,
          issues,
          warnings,
          notices,
          tasks,
          moves
        ],
        ">",
        opts,
        fn str, _ -> str end
      )
    end
  end

  @doc "Returns a new igniter"
  @spec new() :: t()
  def new do
    %__MODULE__{rewrite: Rewrite.new()}
    |> include_existing_elixir_file(".igniter.exs", required?: false)
    |> parse_igniter_config()
  end

  def move_file(igniter, from, from, opts \\ [])
  def move_file(igniter, from, from, _opts), do: igniter

  def move_file(igniter, from, to, opts) do
    case Enum.find(igniter.moves, fn {_key, value} -> value == from end) do
      {key, _} ->
        move_file(igniter.moves, key, to)

      _ ->
        if exists?(igniter, to) || match?({:ok, _}, Rewrite.source(igniter.rewrite, to)) do
          if Keyword.get(opts, :error_if_exists?, true) do
            add_issue(igniter, "Cannot move #{from} to #{to}, as #{to} already exists.")
          else
            igniter
          end
        else
          igniter = include_existing_file(igniter, from)

          source = Rewrite.source!(igniter.rewrite, from)

          if Rewrite.Source.from?(source, :string) do
            rewrite =
              igniter.rewrite
              |> Rewrite.drop([source.path])
              |> Rewrite.put!(%{source | path: to})

            %{igniter | rewrite: rewrite}
          else
            %{igniter | moves: Map.put(igniter.moves, from, to)}
          end
        end
    end
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

  def update_assign(igniter, key, default, fun) do
    %{igniter | assigns: Map.update(igniter.assigns, key, default, fun)}
  end

  defp assign_private(igniter, key, value) do
    %{
      igniter
      | assigns: Map.update(igniter.assigns, :private, %{key => value}, &Map.put(&1, key, value))
    }
  end

  @doc "Includes all files matching the given glob, expecting them all (for now) to be elixir files."
  @spec include_glob(t, Path.t() | GlobEx.t()) :: t()
  def include_glob(igniter, glob) do
    glob =
      case glob do
        %{__struct__: GlobEx} = glob -> glob
        string -> GlobEx.compile!(Path.expand(string))
      end

    paths =
      if igniter.assigns[:test_mode?] do
        igniter.assigns[:test_files]
        |> Map.keys()
        |> Enum.filter(&GlobEx.match?(glob, Path.expand(&1)))
      else
        glob
        |> GlobEx.ls()
      end
      |> Stream.filter(fn path ->
        if Path.extname(path) in [".ex", ".exs"] do
          true
        else
          raise ArgumentError,
                "Cannot include #{inspect(path)} because it is not an Elixir file. This can be supported in the future, but the work hasn't been done yet."
        end
      end)
      |> Stream.map(&Path.relative_to_cwd/1)
      |> Enum.reject(fn path ->
        Rewrite.has_source?(igniter.rewrite, path)
      end)

    paths
    |> Task.async_stream(
      fn path ->
        read_ex_source!(igniter, path)
      end,
      timeout: :infinity
    )
    |> Enum.reduce(igniter, fn {:ok, source}, igniter ->
      %{igniter | rewrite: Rewrite.put!(igniter.rewrite, source)}
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
        %{__struct__: GlobEx} = glob -> glob
        string -> GlobEx.compile!(Path.expand(string))
      end

    igniter = include_glob(igniter, glob)

    igniter.rewrite
    |> Task.async_stream(
      fn source ->
        if GlobEx.match?(glob, Path.expand(source.path)) do
          quoted = Rewrite.Source.get(source, :quoted)
          zipper = Sourceror.Zipper.zip(quoted)

          case func.(zipper) do
            %Sourceror.Zipper{} = new_zipper ->
              if zipper.node != new_zipper.node do
                {source, {:ok, new_zipper}}
              end

            {:ok, %Sourceror.Zipper{} = new_zipper} ->
              if zipper.node != new_zipper.node do
                {source, {:ok, new_zipper}}
              end

            other ->
              {source, other}
          end
        else
        end
      end,
      timeout: :infinity
    )
    |> Stream.reject(fn
      {:ok, nil} ->
        true

      _ ->
        false
    end)
    |> Enum.reduce({igniter, []}, fn {:ok, {source, res}}, {igniter, paths} ->
      case res do
        {:ok, %Sourceror.Zipper{} = zipper} ->
          try do
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
            |> then(fn igniter ->
              {igniter, [source.path | paths]}
            end)
          rescue
            e ->
              reraise e, __STACKTRACE__
          end

        {:error, error} ->
          Rewrite.update!(
            igniter.rewrite,
            Rewrite.Source.add_issues(source, List.wrap(error))
          )
          |> then(&Map.put(igniter, :rewrite, &1))
          |> then(fn igniter ->
            {igniter, paths}
          end)

        {:warning, warning} ->
          {Igniter.add_warning(igniter, warning), paths}
      end
    end)
    |> then(fn {igniter, paths} ->
      format(igniter, paths)
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

  @doc "Adds a notice to the notices list. Notices are displayed to the user once the igniter finishes running."
  @spec add_notice(t, String.t()) :: t()
  def add_notice(igniter, notice) do
    if notice in igniter.notices do
      igniter
    else
      %{igniter | notices: [notice] ++ igniter.notices}
    end
  end

  @doc "Adds a task to the tasks list. Tasks will be run after all changes have been commited"
  def add_task(igniter, task, argv \\ []) when is_binary(task) do
    %{igniter | tasks: igniter.tasks ++ [{task, argv}]}
  end

  @doc """
  Finds the `Igniter.Mix.Task` task by name and composes it (calls its `igniter/2`) into the current igniter.
  If the task doesn't exist, a fallback implementation may be provided as the last argument.
  """
  def compose_task(igniter, task, argv \\ [], fallback \\ nil)

  def compose_task(igniter, task, argv, fallback) when is_atom(task) do
    Code.ensure_compiled!(task)

    if function_exported?(task, :igniter, 2) do
      if !task.supports_umbrella?() && Mix.Project.umbrella?() do
        add_issue(igniter, "Cannot run #{inspect(task)} in an umbrella project.")
      else
        task.igniter(igniter, argv)
      end
    else
      if is_function(fallback) do
        fallback.(igniter, argv)
      else
        # we don't warn because not all packages know about igniter, but they may have their own installers
        # we can't assume that we should call them because they may have required arguments.

        # add_issue(
        #   igniter,
        #   "#{inspect(task)} does not implement `Igniter.igniter/2` and no alternative implementation was provided."
        # )
        igniter
      end
    end
  end

  def compose_task(igniter, task_name, argv, fallback) do
    if igniter.issues == [] do
      task_name
      |> Mix.Task.get()
      |> case do
        nil ->
          if is_function(fallback) do
            fallback.(igniter, argv)
          else
            add_issue(
              igniter,
              "Task #{inspect(task_name)}  could not be found."
            )
          end

        task ->
          compose_task(igniter, task, argv, fallback)
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
      igniter
      |> apply_func_with_zipper(path, func)
      |> format(path)
    else
      if exists?(igniter, path) do
        source = read_ex_source!(igniter, path)

        %{igniter | rewrite: Rewrite.put!(igniter.rewrite, source)}
        |> format(path)
        |> apply_func_with_zipper(path, func)
        |> format(path)
      else
        add_issue(igniter, "Required #{path} but it did not exist")
      end
    end
  end

  @doc "Checks if a file exists on the file system or in the igniter."
  @spec exists?(t(), Path.t()) :: boolean()
  def exists?(igniter, path) do
    cond do
      Rewrite.has_source?(igniter.rewrite, path) ->
        true

      igniter.assigns[:test_mode?] ->
        Map.has_key?(igniter.assigns[:test_files], path)

      true ->
        File.exists?(path)
    end
  end

  @doc """
  Updates a given file's `Rewrite.Source`
  """
  @spec update_file(t(), Path.t(), (Rewrite.Source.t() -> Rewrite.Source.t())) :: t()
  def update_file(igniter, path, updater, opts \\ []) do
    source_handler = source_handler(path, opts)

    if Rewrite.has_source?(igniter.rewrite, path) do
      %{igniter | rewrite: Rewrite.update!(igniter.rewrite, path, updater)}
    else
      if exists?(igniter, path) do
        source = read_source!(igniter, path, source_handler)

        %{igniter | rewrite: Rewrite.put!(igniter.rewrite, source)}
        |> maybe_format(path, true, Keyword.put(opts, :source_handler, source_handler))
        |> Map.update!(:rewrite, fn rewrite ->
          source = Rewrite.source!(rewrite, path)
          Rewrite.update!(rewrite, path, updater.(source))
        end)
      else
        add_issue(igniter, "Required #{path} but it did not exist")
      end
    end
  end

  @deprecated "Use `include_existing_file/3` instead"
  @spec include_existing_elixir_file(t(), Path.t(), opts :: Keyword.t()) :: t()
  def include_existing_elixir_file(igniter, path, opts \\ []) do
    include_existing_file(igniter, path, Keyword.put(opts, :source_handler, Rewrite.Source.Ex))
  end

  @doc "Includes the given file in the project, expecting it to exist. Does nothing if its already been added."
  @spec include_existing_file(t(), Path.t(), opts :: Keyword.t()) :: t()
  def include_existing_file(igniter, path, opts \\ []) do
    required? = Keyword.get(opts, :required?, false)
    source_handler = source_handler(path, opts)

    if Rewrite.has_source?(igniter.rewrite, path) do
      igniter
    else
      if exists?(igniter, path) do
        source = read_source!(igniter, path, source_handler)

        %{igniter | rewrite: Rewrite.put!(igniter.rewrite, source)}
        |> maybe_format(path, false, opts)
      else
        if required? do
          add_issue(igniter, "Required #{path} but it did not exist")
        else
          igniter
        end
      end
    end
  end

  @deprecated "Use `include_or_create_file/3` instead"
  @spec include_or_create_elixir_file(t(), Path.t(), contents :: String.t()) :: t()
  def include_or_create_elixir_file(igniter, path, contents \\ "") do
    include_or_create_file(igniter, path, contents)
  end

  @doc "Includes or creates the given file in the project with the provided contents. Does nothing if its already been added."
  @spec include_or_create_file(t(), Path.t(), contents :: String.t()) :: t()
  def include_or_create_file(igniter, path, contents \\ "") do
    if Rewrite.has_source?(igniter.rewrite, path) do
      igniter
    else
      source_handler = source_handler(path)

      source =
        try do
          read_source!(igniter, path, source_handler)
        rescue
          _ ->
            ""
            |> Rewrite.Source.Ex.from_string(path)
            |> Rewrite.Source.update(:file_creator, :content, contents)
        end

      %{igniter | rewrite: Rewrite.put!(igniter.rewrite, source)}
      |> maybe_format(path, true, source_handler: source_handler)
    end
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
          {false, read_ex_source!(igniter, path)}
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

  @doc "Creates the given file in the project with the provided string contents, or updates it with a function as in `update_file/3` (or with `zipper_updater()` for elixir files) if it already exists."
  def create_or_update_file(igniter, path, contents, updater) do
    if Rewrite.has_source?(igniter.rewrite, path) do
      igniter
      |> update_file(path, updater)
    else
      source_handler = source_handler(path)

      {created?, source} =
        try do
          {false, read_source!(igniter, path, source_handler)}
        rescue
          _ ->
            {true,
             ""
             |> source_handler.from_string(path)
             |> Rewrite.Source.update(:file_creator, :content, contents)}
        end

      %{igniter | rewrite: Rewrite.put!(igniter.rewrite, source)}
      |> maybe_format(path, true, source_handler: source_handler)
      |> then(fn igniter ->
        if created? do
          igniter
        else
          update_file(igniter, path, updater)
        end
      end)
    end
  end

  @deprecated "Use `create_new_file/4`"
  @spec create_new_elixir_file(t(), Path.t(), String.t()) :: Igniter.t()
  def create_new_elixir_file(igniter, path, contents \\ "", opts \\ []) do
    create_new_file(
      igniter,
      path,
      contents,
      Keyword.put(opts, :source_handler, Rewrite.Source.Ex)
    )
  end

  @doc """
  Copies an EEx template file from  the source path to the target path.

  Accepts the same options as `create_new_file/4`.
  """
  @spec copy_template(
          igniter :: Igniter.t(),
          source :: Path.t(),
          target :: Path.t(),
          assigns :: Keyword.t(),
          opts :: Keyword.t()
        ) :: Igniter.t()
  def copy_template(igniter, source, target, assigns, opts \\ []) do
    contents = EEx.eval_file(source, assigns: assigns)
    create_new_file(igniter, target, contents, opts)
  end

  @doc """
  Creates a new file in the project with the provided string contents. Adds an error if it already exists.

  ## Options

  - `:on_exists` - The action to take if the file already exists. Can be
    - `:error` (default) - Adds an error that prevents any eventual write.
    - `:warning` - Warns when writing but continues (without overwriting)
    - `:skip` - Skips writing the file without a warning
    - `:overwrite` - Warns when writing and overwrites the content with the new content
  """
  @spec create_new_file(t(), Path.t(), String.t()) :: Igniter.t()
  def create_new_file(igniter, path, contents \\ "", opts \\ []) do
    source_handler = source_handler(path, opts)

    {igniter, source} =
      try do
        source = read_source!(igniter, path, source_handler)

        source =
          Rewrite.Source.update(source, :content, contents)

        {already_exists(igniter, path, Keyword.get(opts, :on_exists, :error)), source}
      rescue
        _ ->
          has_source? =
            Rewrite.has_source?(igniter.rewrite, path)

          source =
            ""
            |> source_handler.from_string(path)
            |> Rewrite.Source.update(:file_creator, :content, contents)

          if has_source? do
            {already_exists(igniter, path, Keyword.get(opts, :on_exists, :error)), source}
          else
            {igniter, source}
          end
      end

    sources =
      case opts[:on_exists] do
        :overwrite ->
          Map.put(igniter.rewrite.sources, path, source)

        _ ->
          Map.put_new(igniter.rewrite.sources, path, source)
      end

    %{
      igniter
      | rewrite: %{igniter.rewrite | sources: sources}
    }
    |> maybe_format(path, true, opts)
  end

  defp already_exists(igniter, path, :error) do
    Igniter.add_issue(igniter, "#{path}: File already exists")
  end

  defp already_exists(igniter, path, :warning) do
    Igniter.add_warning(igniter, "#{path}: File already exists")
  end

  defp already_exists(igniter, _path, _) do
    igniter
  end

  defp maybe_format(igniter, path, default_bool, opts) do
    if source_handler(path, opts) == Rewrite.Source.Ex and
         Keyword.get(opts, :format?, default_bool) do
      format(igniter, path)
    else
      igniter
    end
  end

  defp source_handler(path, opts \\ []) do
    Keyword.get_lazy(opts, :source_handler, fn ->
      if Path.extname(path) in Rewrite.Source.Ex.extensions() do
        Rewrite.Source.Ex
      else
        Rewrite.Source
      end
    end)
  end

  @doc """
  Applies the current changes to the `mix.exs` in the Igniter and fetches dependencies.

  Returns the remaining changes in the Igniter if successful.

  ## Options

  * `:error_on_abort?` - If `true`, raises an error if the user aborts the operation. Returns the original igniter if not.
  * `:yes` - If `true`, automatically applies the changes without prompting the user.
  """
  def apply_and_fetch_dependencies(igniter, opts \\ []) do
    if igniter.assigns[:test_mode?] do
      raise "Cannot use `Igniter.apply_and_fetch_dependencies/1-2` in test mode"
    end

    if opts[:force?] ||
         (!igniter.assigns[:private][:refused_fetch_dependencies?] &&
            has_changes?(igniter, ["mix.exs"])) do
      igniter = prompt_on_git_changes(igniter, opts)
      source = Rewrite.source!(igniter.rewrite, "mix.exs")

      original_quoted = Rewrite.Source.get(source, :quoted, 1)
      original_zipper = Zipper.zip(original_quoted)
      quoted = Rewrite.Source.get(source, :quoted)
      zipper = Zipper.zip(quoted)

      with {:ok, original_zipper} <-
             Igniter.Code.Function.move_to_defp(original_zipper, :deps, 0),
           {:ok, zipper} <- Igniter.Code.Function.move_to_defp(zipper, :deps, 0) do
        quoted_with_only_deps_change =
          original_zipper
          |> Igniter.Code.Common.replace_code(zipper.node)
          |> Zipper.topmost()
          |> Zipper.node()

        source = Rewrite.Source.update(source, :quoted, quoted_with_only_deps_change)
        rewrite = Rewrite.update!(igniter.rewrite, source)

        if opts[:force?] || changed?(source) do
          display_diff([source], opts)

          message =
            opts[:message] ||
              if opts[:error_on_abort?] do
                "These dependencies #{IO.ANSI.red()}must#{IO.ANSI.reset()} be installed before continuing. Modify mix.exs and install?"
              else
                "These dependencies #{IO.ANSI.yellow()}should#{IO.ANSI.reset()} be installed before continuing. Modify mix.exs and install?"
              end

          if opts[:yes] || !changed?(source) || Igniter.Util.IO.yes?(message) do
            rewrite =
              case Rewrite.write(rewrite, "mix.exs", :force) do
                {:ok, rewrite} -> rewrite
                {:error, error} -> raise error
              end

            source = Rewrite.source!(rewrite, "mix.exs")
            source = Rewrite.Source.update(source, :quoted, quoted)

            igniter =
              %{igniter | rewrite: Rewrite.update!(rewrite, source)}

            if Keyword.get(opts, :fetch?, true) do
              Igniter.Util.Install.get_deps!(igniter, opts)
            else
              igniter
            end
          else
            if opts[:error_on_abort?] do
              raise "Aborted by the user."
            else
              assign_private(igniter, :refused_fetch_dependencies?, true)
            end
          end
        else
          igniter
        end
      else
        _ ->
          display_diff([source], opts)

          message =
            if opts[:error_on_abort?] do
              "These dependencies #{IO.ANSI.red()}must#{IO.ANSI.reset()} be installed before continuing. Modify mix.exs and install?"
            else
              "These dependencies #{IO.ANSI.yellow()}should#{IO.ANSI.reset()} be installed before continuing. Modify mix.exs and install?"
            end

          if Igniter.Util.IO.yes?(message) do
            rewrite =
              case Rewrite.write(igniter.rewrite, "mix.exs", :force) do
                {:ok, rewrite} -> rewrite
                {:error, error} -> raise error
              end

            igniter =
              Igniter.Util.Install.get_deps!(igniter, opts)

            %{igniter | rewrite: rewrite}
          else
            if opts[:error_on_abort?] do
              raise "Aborted by the user."
            else
              assign_private(igniter, :refused_fetch_dependencies?, true)
            end
          end
      end
    else
      igniter
    end
  end

  @doc "This function stores in the igniter if its been run before, so it is only run once, which is expensive."
  def include_all_elixir_files(igniter) do
    if igniter.assigns[:private][:included_all_elixir_files?] do
      igniter
    else
      igniter
      |> Igniter.Project.IgniterConfig.get(:source_folders)
      |> Enum.reduce(igniter, fn source_folder, igniter ->
        include_glob(igniter, Path.join(source_folder, "/**/*.{ex,exs}"))
      end)
      |> include_glob("{test,config}/**/*.{ex,exs}")
      |> assign_private(:included_all_elixir_files?, true)
    end
  end

  @doc "Runs an update over all elixir files"
  def update_all_elixir_files(igniter, updater) do
    if igniter.assigns[:private][:included_all_elixir_files?] do
      igniter
    else
      igniter
      |> Igniter.Project.IgniterConfig.get(:source_folders)
      |> Enum.reduce(igniter, fn source_folder, igniter ->
        update_glob(igniter, Path.join(source_folder, "/**/*.{ex,exs}"), updater)
      end)
      |> update_glob("{test,config}/**/*.{ex,exs}", updater)
      |> assign_private(:included_all_elixir_files?, true)
    end
  end

  @doc """
  Returns whether the current Igniter has pending changes.
  """
  def has_changes?(igniter, paths \\ nil) do
    paths =
      if paths do
        Enum.map(paths, &Path.relative_to_cwd/1)
      end

    igniter.rewrite
    |> Rewrite.sources()
    |> then(fn sources ->
      if paths do
        sources
        |> Enum.filter(&(&1.path in paths))
      else
        sources
      end
    end)
    |> Enum.any?(fn source ->
      Rewrite.Source.from?(source, :string) || Rewrite.Source.updated?(source)
    end)
  end

  @doc """
  Executes or dry-runs a given Igniter.
  """
  def do_or_dry_run(igniter, opts \\ []) do
    if igniter.assigns[:test_mode?] do
      raise ArgumentError,
            "Must `Igniter.Test.apply/1` instead of `Igniter.do_or_dry_run` when running in `test_mode?`."
    end

    igniter = prepare_for_write(igniter)

    title = opts[:title] || "Igniter"

    halt_if_fails_check!(igniter, title, opts)

    case igniter do
      %{issues: []} ->
        result_of_dry_run =
          if has_changes?(igniter) do
            if opts[:dry_run] || !opts[:yes] do
              Mix.shell().info("\n#{IO.ANSI.green()}#{title}#{IO.ANSI.reset()}:")

              display_diff(Rewrite.sources(igniter.rewrite), opts)
            end

            :dry_run_with_changes
          else
            unless opts[:quiet_on_no_changes?] || opts[:yes] do
              Mix.shell().info("\n#{title}:\n\n    No proposed content changes!\n")

              display_notices(igniter)
            end

            :dry_run_with_no_changes
          end

        display_warnings(igniter, title)

        display_moves(igniter)

        display_tasks(igniter, result_of_dry_run, opts)

        if opts[:dry_run] ||
             (result_of_dry_run == :dry_run_with_no_changes && Enum.empty?(igniter.tasks) &&
                Enum.empty?(igniter.moves)) do
          result_of_dry_run
        else
          if opts[:yes] ||
               Igniter.Util.IO.yes?(message_with_git_warning(igniter, opts)) do
            igniter.rewrite
            |> Enum.any?(fn source ->
              Rewrite.Source.from?(source, :string) || Rewrite.Source.updated?(source)
            end)
            |> Kernel.||(!Enum.empty?(igniter.tasks))
            |> Kernel.||(!Enum.empty?(igniter.moves))
            |> if do
              igniter.rewrite
              |> Rewrite.write_all()
              |> case do
                {:ok, _result} ->
                  unless Enum.empty?(igniter.tasks) do
                    Mix.shell().cmd("mix deps.get")
                  end

                  igniter.moves
                  |> Enum.each(fn {from, to} ->
                    File.mkdir_p!(Path.dirname(to))
                    File.rename!(from, to)
                  end)

                  igniter.tasks
                  |> Enum.each(fn {task, args} ->
                    Mix.shell().cmd("mix #{task} #{Enum.join(args, " ")}")
                  end)

                  display_notices(igniter)

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

  defp halt_if_fails_check!(igniter, title, opts) do
    cond do
      !opts[:check] ->
        :ok

      !Enum.empty?(igniter.warnings) ->
        Mix.shell().error("Warnings would have been emitted and the --check flag was specified.")
        display_warnings(igniter, title)

        System.halt(2)

      !Enum.empty?(igniter.issues) ->
        Mix.shell().error("Errors would have been emitted and the --check flag was specified.")
        igniter_issues(igniter)

        System.halt(3)

      !Enum.empty?(igniter.tasks) ->
        Mix.shell().error("Tasks would have been run and the --check flag was specified.")
        display_tasks(igniter, :dry_run_with_no_changes, [])

        System.halt(3)

      !Enum.empty?(igniter.moves) ->
        Mix.shell().error("Files would have been moved and the --check flag was specified.")
        display_moves(igniter)

        System.halt(3)

      Igniter.has_changes?(igniter) ->
        Mix.shell().error(
          "Changes have been made to the project and the --check flag was specified."
        )

        display_diff(Rewrite.sources(igniter.rewrite), opts)

        System.halt(1)
    end
  end

  defp prompt_on_git_changes(igniter, opts) do
    if opts[:dry_run] || opts[:yes] || igniter.assigns[:test_mode?] || !has_changes?(igniter) do
      igniter
    else
      if Map.get(igniter.assigns, :prompt_on_git_changes?, true) do
        case check_git_status() do
          {:dirty, output} ->
            if Igniter.Util.IO.yes?("""
               #{IO.ANSI.red()} Uncommitted changes detected in the project. #{IO.ANSI.reset()}

               Output of `git status -s --porcelain`:

               #{output}

               Continue? You will be prompted again to accept the above changes.
               """) do
              Igniter.assign(igniter, :prompt_on_git_changes?, false)
            else
              exit({:shutdown, 1})
            end

          _ ->
            Igniter.assign(igniter, :prompt_on_git_changes?, false)
        end
      else
        igniter
      end
    end
  end

  defp message_with_git_warning(igniter, opts) do
    message = opts[:message] || "Proceed with changes?"

    if opts[:dry_run] || opts[:yes] || igniter.assigns[:test_mode?] || !has_changes?(igniter) do
      message
    else
      if Map.get(igniter.assigns, :prompt_on_git_changes?, true) do
        case check_git_status() do
          {:dirty, output} ->
            """
            #{IO.ANSI.red()}Warning! Uncommitted git changes detected in the project. #{IO.ANSI.reset()}

            Output of `git status -s --porcelain`:

            #{output}

            #{message}
            """

          _ ->
            message
        end
      else
        message
      end
    end
  end

  defp display_diff(sources, opts) do
    unless opts[:yes] do
      Mix.shell().info(diff(sources))
    end
  end

  @doc false
  def diff(sources, opts \\ []) do
    color? = Keyword.get(opts, :color?, true)

    Enum.map_join(sources, "\n", fn source ->
      source =
        case source do
          {_, source} -> source
          source -> source
        end

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

            "#{String.pad_trailing(to_string(line_number), space_padding)} #{color(IO.ANSI.yellow(), color?)}| #{color(IO.ANSI.green(), color?)}#{line}#{color(IO.ANSI.reset(), color?)}"
          end)

        if String.trim(diffish_looking_text) != "" do
          """
          Create: #{Rewrite.Source.get(source, :path)}

          #{diffish_looking_text}
          """
        else
          ""
        end
      else
        diff = Rewrite.Source.diff(source, color: color?) |> IO.iodata_to_binary()

        if String.trim(diff) != "" do
          """
          Update: #{Rewrite.Source.get(source, :path)}

          #{diff}
          """
        else
          ""
        end
      end
    end)
  end

  defp color(color, true), do: color
  defp color(_, _), do: ""

  defp igniter_issues(igniter) do
    issues =
      Enum.map_join(igniter.issues, "\n", fn error ->
        if is_binary(error) do
          "* #{IO.ANSI.red()}#{error}#{IO.ANSI.reset()}"
        else
          "* #{IO.ANSI.red()}#{Exception.format(:error, error)}#{IO.ANSI.red()}"
        end
      end)

    Mix.shell().info("""
    Issues during code generation

    #{issues}
    """)
  end

  defp format(igniter, adding_paths, reevaluate_igniter_config? \\ true) do
    igniter =
      igniter
      |> include_existing_elixir_file("config/config.exs", require?: false)
      |> include_existing_elixir_file("config/#{Mix.env()}.exs", require?: false)

    if adding_paths &&
         Enum.any?(List.wrap(adding_paths), &(Path.basename(&1) == ".formatter.exs")) do
      format(igniter, nil, false)
      |> reevaluate_igniter_config(adding_paths, reevaluate_igniter_config?)
    else
      igniter =
        "**/.formatter.exs"
        |> Path.wildcard()
        |> Enum.reduce(igniter, fn path, igniter ->
          Igniter.include_existing_file(igniter, path)
        end)

      igniter =
        if exists?(igniter, ".formatter.exs") do
          Igniter.include_existing_file(igniter, ".formatter.exs")
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

          if is_nil(adding_paths) || path in List.wrap(adding_paths) do
            dir = Path.dirname(path)

            opts =
              case find_formatter_exs_file_options(dir, formatter_exs_files, Path.extname(path)) do
                :error ->
                  []

                {:ok, opts} ->
                  opts
              end

            try do
              formatted =
                with_evaled_configs(rewrite, fn ->
                  Rewrite.Source.Ex.format(source, opts)
                end)

              source
              |> Rewrite.Source.Ex.put_formatter_opts(opts)
              |> Rewrite.Source.update(:content, formatted)
            rescue
              e ->
                Rewrite.Source.add_issue(source, """
                Igniter would have produced invalid syntax.

                This is almost certainly a bug in Igniter, or in the implementation
                of the task/function you are using.

                #{Exception.format(:error, e, __STACKTRACE__)}
                """)
            end
          else
            source
          end
        end)

      %{igniter | rewrite: rewrite}
      |> reevaluate_igniter_config(adding_paths, reevaluate_igniter_config?)
    end
  end

  defp reevaluate_igniter_config(igniter, adding_paths, true) do
    if is_nil(adding_paths) || ".igniter.exs" in List.wrap(adding_paths) do
      parse_igniter_config(igniter)
    else
      igniter
    end
  end

  defp reevaluate_igniter_config(igniter, _adding_paths, false) do
    igniter
  end

  # for now we only eval `config.exs`
  defp with_evaled_configs(rewrite, fun) do
    [
      Rewrite.source(rewrite, "config/config.exs"),
      Rewrite.source(rewrite, "config/#{Mix.env()}.exs")
    ]
    |> Enum.flat_map(fn
      {:ok, source} ->
        [Rewrite.Source.get(source, :quoted)]

      _ ->
        []
    end)
    |> case do
      [] ->
        fun.()

      contents ->
        to_set =
          {:__block__, [], contents}
          |> Sourceror.Zipper.zip()
          # replace with nil
          |> Igniter.Code.Common.remove(
            &Igniter.Code.Function.function_call?(&1, :import_config, 1)
          )
          |> Zipper.topmost_root()
          |> Sourceror.to_string()
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

  defp eval_file_with_keyword_list(path) do
    {opts, _} = Code.eval_file(path)

    unless Keyword.keyword?(opts) do
      raise "Expected #{inspect(path)} to return a keyword list, got: #{inspect(opts)}"
    end

    opts
  end

  defp apply_func_with_zipper(igniter, path, func) do
    source = Rewrite.source!(igniter.rewrite, path)
    quoted = Rewrite.Source.get(source, :quoted)
    zipper = Sourceror.Zipper.zip(quoted)

    res =
      case func.(zipper) do
        %Sourceror.Zipper{} = zipper ->
          {:ok, zipper}

        other ->
          other
      end

    case res do
      {:ok, %Sourceror.Zipper{} = zipper} ->
        try do
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
        rescue
          e ->
            reraise e, __STACKTRACE__
        end

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

  defp read_ex_source!(igniter, path) do
    read_source!(igniter, path, Rewrite.Source.Ex)
  end

  defp read_source!(igniter, path, source_handler) do
    if igniter.assigns[:test_mode?] do
      if content = igniter.assigns[:test_files][path] do
        source_handler.from_string(content, path)
        |> Map.put(:from, :file)
      else
        raise "File #{path} not found in test files."
      end
    else
      source_handler.read!(path)
    end
  end

  @doc false
  def prepare_for_write(igniter) do
    source_issues =
      Enum.flat_map(igniter.rewrite, fn source ->
        changed_issues =
          if igniter.assigns[:test_mode?] do
            []
          else
            if Rewrite.Source.file_changed?(source) do
              ["File has been changed since it was originally read."]
            else
              []
            end
          end

        issues = Enum.uniq(changed_issues ++ Rewrite.Source.issues(source))

        case issues do
          [] ->
            []

          issues ->
            Enum.map(issues, fn issue ->
              "#{source.path}: #{issue}"
            end)
        end
      end)

    needs_test_support? =
      Enum.any?(igniter.rewrite, fn source ->
        Path.extname(source.path) == ".ex" &&
          source.path
          |> Path.split()
          |> List.starts_with?(["test", "support"])
      end)

    %{
      igniter
      | issues: Enum.uniq(igniter.issues ++ source_issues),
        warnings: Enum.uniq(igniter.warnings),
        tasks: Enum.uniq(igniter.tasks)
    }
    |> Igniter.Project.Module.move_files()
    |> remove_unchanged_files()
    |> then(fn igniter ->
      if needs_test_support? do
        Igniter.Project.Test.ensure_test_support(igniter)
      else
        igniter
      end
    end)
  end

  defp remove_unchanged_files(igniter) do
    igniter.rewrite
    |> Enum.flat_map(fn source ->
      if Rewrite.Source.from?(source, :string) || changed?(source) do
        []
      else
        [source.path]
      end
    end)
    |> then(fn paths ->
      %{igniter | rewrite: Rewrite.drop(igniter.rewrite, paths)}
    end)
  end

  defp parse_igniter_config(igniter) do
    case Rewrite.source(igniter.rewrite, ".igniter.exs") do
      {:error, _} ->
        assign(igniter, :igniter_exs, [])

      {:ok, source} ->
        {igniter_exs, _} = Rewrite.Source.get(source, :quoted) |> Code.eval_quoted()

        assign(
          igniter,
          :igniter_exs,
          Keyword.update(igniter_exs, :extensions, [], fn extensions ->
            Enum.map(extensions, fn
              {extension, opts} ->
                {extension, opts}

              extension ->
                {extension, []}
            end)
          end)
        )
    end
  end

  @doc "Returns true if any of the files specified in `paths` have changed."
  @spec changed?(t(), String.t() | list(String.t())) :: boolean()
  def changed?(%Igniter{} = igniter, paths) do
    paths = List.wrap(paths)

    igniter.rewrite
    |> Rewrite.sources()
    |> Enum.filter(&(&1.path in paths))
    |> Enum.any?(&changed?/1)
  end

  @doc "Returns true if the igniter or source provided has changed"
  @spec changed?(t() | Rewrite.Source.t()) :: boolean()
  def changed?(%Igniter{} = igniter) do
    igniter.rewrite
    |> Rewrite.sources()
    |> Enum.any?(&changed?/1)
  end

  def changed?(%Rewrite.Source{} = source) do
    diff = Rewrite.Source.diff(source) |> IO.iodata_to_binary()

    String.trim(diff) != ""
  end

  defp display_warnings(%{warnings: []}, _title), do: :ok

  defp display_warnings(%{warnings: warnings}, title) do
    Mix.shell().info("\n#{title} - #{IO.ANSI.yellow()}Warnings:#{IO.ANSI.reset()}\n")

    warnings =
      warnings
      |> Enum.map_join("\n\n", fn error ->
        if is_binary(error) do
          "* #{IO.ANSI.yellow()}#{error}#{IO.ANSI.reset()}"
        else
          "* #{IO.ANSI.yellow()}#{Exception.format(:error, error)}#{IO.ANSI.reset()}"
        end
      end)

    Mix.shell().info(warnings <> "\n\n")
  end

  defp display_notices(igniter) do
    case igniter.notices do
      [] ->
        :ok

      notices ->
        notices =
          Enum.map_join(notices, "\n\n", fn notice ->
            "#{IO.ANSI.green()}#{notice}#{IO.ANSI.reset()}"
          end)

        Mix.shell().info("\n" <> notices)
    end
  end

  defp display_moves(%{moves: moves}) when moves == %{}, do: :ok

  defp display_moves(%{moves: moves}) do
    Mix.shell().info("The following files will be moved:")

    Enum.each(moves, fn {from, to} ->
      Mix.shell().info(
        "#{IO.ANSI.red()}#{from}#{IO.ANSI.reset()}: #{IO.ANSI.green()}#{to}#{IO.ANSI.reset()}"
      )
    end)
  end

  defp display_tasks(igniter, result_of_dry_run, opts) do
    if igniter.tasks != [] && !opts[:yes] do
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
  end

  defp check_git_status do
    case System.cmd("git", ["status", "-s", "--porcelain"], stderr_to_stdout: true) do
      {"", _} ->
        :clean

      {output, 0} ->
        {:dirty, output}

      _ ->
        :error
    end
  rescue
    _ ->
      :unavailable
  end
end
