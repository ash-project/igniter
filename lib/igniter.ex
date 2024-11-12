defmodule Igniter do
  @moduledoc """
  Tools for generating and patching code into an Elixir project.
  """

  defstruct [
    :rewrite,
    issues: [],
    tasks: [],
    warnings: [],
    notices: [],
    assigns: %{},
    moves: %{},
    args: %Igniter.Mix.Task.Args{}
  ]

  alias Sourceror.Zipper

  @type t :: %__MODULE__{
          rewrite: Rewrite.t(),
          issues: [String.t()],
          tasks: [String.t() | {String.t(), list(String.t())}],
          warnings: [String.t()],
          notices: [String.t()],
          assigns: map(),
          moves: %{optional(String.t()) => String.t()},
          args: Igniter.Mix.Task.Args.t()
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
    %__MODULE__{
      rewrite:
        Rewrite.new(
          hooks: [Igniter.Rewrite.DotFormatterUpdater],
          dot_formatter: Rewrite.DotFormatter.read!(nil, ignore_unknown_deps: true)
        )
    }
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
        %{__struct__: GlobEx} = glob ->
          if Path.type(glob.source) == :relative do
            GlobEx.compile!(Path.expand(glob.source))
          else
            glob
          end

        string ->
          GlobEx.compile!(Path.expand(string))
      end

    if igniter.assigns[:test_mode?] do
      igniter.assigns[:test_files]
      |> Map.keys()
      |> Enum.filter(fn key ->
        expanded = Path.expand(key)
        glob.source == expanded || GlobEx.match?(glob, expanded)
      end)
      |> Enum.map(&Path.relative_to_cwd/1)
      |> Enum.reject(fn path ->
        Rewrite.has_source?(igniter.rewrite, path)
      end)
      |> Enum.map(fn path ->
        source_handler = source_handler(path)

        read_source!(igniter, path, source_handler)
      end)
      |> Enum.reduce(igniter, fn source, igniter ->
        %{igniter | rewrite: Rewrite.put!(igniter.rewrite, source)}
      end)
    else
      %{igniter | rewrite: Rewrite.read!(igniter.rewrite, glob)}
    end
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
              update_source(
                source,
                igniter,
                :quoted,
                Sourceror.Zipper.topmost_root(zipper),
                by: :configure
              )
            )
            |> then(&Map.put(igniter, :rewrite, &1))
            |> then(fn igniter ->
              {igniter, [source.path | paths]}
            end)
          rescue
            e ->
              reraise """
                      Failed to set the new source for the file, for `#{source.path}`

                      Source:

                      #{Igniter.Util.Debug.code_at_node(Zipper.topmost(zipper))}

                      Error:

                      #{Exception.format(:error, e)}

                      """,
                      __STACKTRACE__
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
  Finds the `Igniter.Mix.Task` task by name and composes it with `igniter`.

  If the task doesn't exist, a `fallback` function may be provided. This
  function should accept and return the `igniter`.

  ## Argument handling

  This function calls the task's `igniter/1` (or `igniter/2`) callback, setting
  `igniter.args` using the current `igniter.args.argv_flags`. This prevents
  composed tasks from accidentally consuming positional arguments. If you
  wish the composed task to access additional arguments, you must explicitly
  pass an `argv` list.

  Additionally, you must declare other tasks you are composing with in your
  task's `Igniter.Mix.Task.Info` struct using the `:composes` key. Without
  this, you'll see unexpected argument errors if a flag that a composed task
  uses is passed without you explicitly declaring it in your `:schema`.

  ## Example

      def info(_argv, _parent) do
        %Igniter.Mix.Task.Info{
          ...,
          composes: [
            "other.task1",
            "other.task2"
          ]
        }

      def igniter(igniter) do
        igniter
        # other.task1 will see igniter.args.argv_flags as its args
        |> Igniter.compose_task("other.task1")
        # other.task2 will see an additional arg and flag
        |> Igniter.compose_task("other.task2", ["arg", "--flag"] ++ igniter.argv.argv_flags)
      end

  """
  @spec compose_task(
          t,
          task :: String.t() | module(),
          argv :: list(String.t()) | nil,
          fallback :: (t -> t) | (t, list(String.t()) -> t) | nil
        ) :: t
  def compose_task(igniter, task, argv \\ nil, fallback \\ nil)

  def compose_task(igniter, task, argv, fallback) when is_atom(task) do
    Code.ensure_compiled!(task)

    original_args = igniter.args

    if Igniter.Mix.Task.igniter_task?(task) do
      if !task.supports_umbrella?() && Mix.Project.umbrella?() do
        add_issue(igniter, "Cannot run #{inspect(task)} in an umbrella project.")
      else
        igniter
        |> Igniter.Mix.Task.configure_and_run(task, argv || igniter.args.argv_flags)
        |> Map.replace!(:args, original_args)
      end
    else
      cond do
        is_function(fallback, 1) ->
          fallback.(igniter)

        is_function(fallback, 2) ->
          # TODO: Remove this clause when `igniter/2` is removed
          fallback.(igniter, argv || igniter.args.argv)

        true ->
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
    task_name
    |> Mix.Task.get()
    |> case do
      nil ->
        cond do
          is_function(fallback, 1) ->
            fallback.(igniter)

          is_function(fallback, 2) ->
            # TODO: Remove this clause when `igniter/2` is removed
            fallback.(igniter, argv || igniter.args.argv)

          true ->
            add_issue(
              igniter,
              "Task #{inspect(task_name)} could not be found."
            )
        end

      task ->
        compose_task(igniter, task, argv, fallback)
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
            |> Rewrite.Source.Ex.from_string(path: path)
            |> update_source(igniter, :content, contents, by: :file_creator)
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
             |> update_source(igniter, :content, contents, by: :file_creator)}
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
             |> update_source(igniter, :content, contents, by: :file_creator)}
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

        source = update_source(source, igniter, :content, contents)

        {already_exists(igniter, path, Keyword.get(opts, :on_exists, :error)), source}
      rescue
        _ ->
          has_source? =
            Rewrite.has_source?(igniter.rewrite, path)

          source =
            ""
            |> source_handler.from_string(path: path)
            |> update_source(igniter, :content, contents, by: :file_creator)

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

        source = update_source(source, igniter, :quoted, quoted_with_only_deps_change)
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
            source = update_source(source, igniter, :quoted, quoted)

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
            if !(opts[:quiet_on_no_changes?] || opts[:yes]) do
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
                  if !Enum.empty?(igniter.tasks) do
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
                  |> display_issues()

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
        display_issues(igniter)
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
        display_issues(igniter)

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
    if !opts[:yes] do
      Mix.shell().info(diff(sources))
    end
  end

  @doc false
  def diff(sources, opts \\ []) do
    color? = Keyword.get(opts, :color?, true)

    Enum.map_join(sources, fn source ->
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

        space_padding =
          content_lines
          |> length()
          |> to_string()
          |> String.length()

        diffish_looking_text =
          content_lines
          |> Enum.with_index(1)
          |> Enum.map_join(fn {line, line_number} ->
            IO.ANSI.format(
              [
                String.pad_trailing(to_string(line_number), space_padding),
                " ",
                :yellow,
                "|",
                :green,
                line,
                "\n"
              ],
              color?
            )
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

  @doc false
  def format(igniter, adding_paths, reevaluate_igniter_config? \\ true) do
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
      dot_formatter = Rewrite.dot_formatter(rewrite)

      rewrite =
        Enum.reduce(rewrite, rewrite, fn source, rewrite ->
          path = source |> Rewrite.Source.get(:path)

          if is_nil(adding_paths) || path in List.wrap(adding_paths) do
            source =
              try do
                formatted =
                  with_evaled_configs(rewrite, fn ->
                    source
                    |> Rewrite.Source.format!(dot_formatter: dot_formatter)
                    |> Rewrite.Source.get(:content)
                  end)

                update_source(source, igniter, :content, formatted)
              rescue
                e ->
                  Rewrite.Source.add_issue(source, """
                  Igniter would have produced invalid syntax.

                  This is almost certainly a bug in Igniter, or in the implementation
                  of the task/function you are using.

                  #{Exception.format(:error, e, __STACKTRACE__)}
                  """)
              end

            Rewrite.update!(rewrite, source)
          else
            rewrite
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
            update_source(
              source,
              igniter,
              :quoted,
              Sourceror.Zipper.root(zipper),
              by: :configure
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

  defp read_ex_source!(igniter, path) do
    read_source!(igniter, path, Rewrite.Source.Ex)
  end

  defp read_source!(igniter, path, source_handler) do
    if igniter.assigns[:test_mode?] do
      if content = igniter.assigns[:test_files][path] do
        source_handler.from_string(content, path: path)
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

  @doc false
  def update_source(%Rewrite.Source{} = source, %Igniter{} = igniter, key, value, opts \\ []) do
    opts = Keyword.put_new(opts, :dot_formatter, Rewrite.dot_formatter(igniter.rewrite))
    Rewrite.Source.update(source, key, value, opts)
  end

  @doc false
  def display_issues(igniter) do
    igniter.issues
    |> Enum.reverse()
    |> Enum.map(fn error ->
      ["* ", :red, format_error(error)]
    end)
    |> display_list([:red, "Issues:"])
  end

  @doc false
  def display_warnings(igniter, title) do
    igniter.warnings
    |> Enum.reverse()
    |> Enum.map(fn error ->
      ["* ", :yellow, format_error(error)]
    end)
    |> display_list([title, " - ", :yellow, "Warnings:"])
  end

  @doc false
  def display_notices(igniter) do
    igniter.notices
    |> Enum.reverse()
    |> Enum.map(fn notice ->
      [:green, "Notice: ", :reset, notice]
    end)
    |> display_list()
  end

  @doc false
  def display_moves(igniter) do
    igniter.moves
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {from, to} ->
      [:red, from, :reset, ": ", :green, to]
    end)
    |> display_list("These files will be moved:")
  end

  @doc false
  def display_tasks(igniter, result_of_dry_run, opts) do
    if !opts[:yes] do
      title =
        if result_of_dry_run == :dry_run_with_no_changes do
          "These tasks will be run:"
        else
          "These tasks will be run after the above changes:"
        end

      igniter.tasks
      |> Enum.map(fn {task, args} ->
        ["* ", :red, task, " ", :yellow, Enum.intersperse(args, " ")]
      end)
      |> display_list(title)
    end
  end

  @spec display_list(IO.ANSI.ansidata(), IO.ANSI.ansidata()) :: :ok
  defp display_list(list, title \\ nil)

  defp display_list([], _title), do: :ok

  defp display_list(list, title) do
    title = if title, do: [IO.ANSI.format(title), "\n\n"], else: []
    formatted_list = Enum.map_join(list, "\n", &IO.ANSI.format/1)

    Mix.shell().info(["\n", title, formatted_list, "\n"])
  end

  defp format_error(%{__exception__: true} = exception) do
    Exception.format(:error, exception)
  end

  defp format_error(error) when is_binary(error), do: error

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
