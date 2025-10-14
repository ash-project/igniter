# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule Igniter do
  @moduledoc """
  Tools for generating and patching code into an Elixir project.

  ## Assigns

  Assigns are a way to store arbitrary data on an Igniter struct that can be used to
  pass information between tasks, configure behavior, or maintain state throughout
  the execution pipeline. They work similarly to assigns in Phoenix LiveView or Plug.

  You can set assigns using `assign/3` or `assign/2`, and access them via the
  `assigns` field on the Igniter struct.

  ### Special Assigns

  The following assigns have special meaning and can be set to control Igniter's behavior:

  * `:prompt_on_git_changes?` - Controls whether Igniter should warn users about
    uncommitted git changes before applying modifications. Defaults to `true`. When
    enabled, Igniter will check git status and display a warning if there are
    uncommitted changes, giving users a chance to save their work before proceeding.

  * `:quiet_on_no_changes?` - Controls whether Igniter should display a message when
    no changes are proposed. Defaults to `false`. When set to `true`, Igniter will
    suppress the "No proposed content changes!" message that normally appears when
    running operations that don't result in any file modifications.
  """

  defstruct [
    :rewrite,
    task: nil,
    parent: nil,
    issues: [],
    tasks: [],
    warnings: [],
    notices: [],
    assigns: %{},
    mkdirs: [],
    rms: [],
    moves: %{},
    args: %Igniter.Mix.Task.Args{}
  ]

  alias Sourceror.Zipper

  @type t :: %__MODULE__{
          rewrite: Rewrite.t(),
          issues: [String.t()],
          tasks: [
            String.t() | {String.t(), list(String.t())} | {String.t(), list(String.t()), :delayed}
          ],
          warnings: [String.t()],
          notices: [String.t()],
          assigns: map(),
          mkdirs: [String.t()],
          rms: [String.t()],
          moves: %{optional(String.t()) => String.t()},
          args: Igniter.Mix.Task.Args.t()
        }

  @type zipper_updater ::
          (Zipper.t() ->
             {:ok, Zipper.t()}
             | {:error, String.t() | [String.t()]}
             | {:warning, String.t() | [String.t()]})

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
          dot_formatter:
            Rewrite.DotFormatter.read!(nil,
              ignore_unknown_deps: true,
              ignore_missing_sub_formatters: true
            )
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
          if Path.type(glob.source) == :absolute do
            GlobEx.compile!(
              Igniter.Util.BackwardsCompat.relative_to_cwd(glob.source, force: true)
            )
          else
            glob
          end

        string ->
          GlobEx.compile!(string)
      end

    if igniter.assigns[:test_mode?] do
      igniter.assigns[:test_files]
      |> Map.keys()
      |> Enum.filter(fn key ->
        expanded = Path.expand(key)
        glob.source == expanded || GlobEx.match?(glob, expanded)
      end)
      |> Enum.map(&Igniter.Util.BackwardsCompat.relative_to_cwd(&1, force: true))
      |> Enum.reject(fn path ->
        Rewrite.has_source?(igniter.rewrite, path) || path in igniter.rms
      end)
      |> Enum.map(fn path ->
        source_handler = source_handler(path)
        path = Igniter.Util.BackwardsCompat.relative_to_cwd(path, force: true)

        read_source!(igniter, path, source_handler)
      end)
      |> Enum.reduce(igniter, fn source, igniter ->
        %{igniter | rewrite: Rewrite.put!(igniter.rewrite, source)}
      end)
    else
      igniter.rewrite
      |> Rewrite.read!(glob)
      |> Map.update!(:sources, fn sources ->
        Map.drop(sources, igniter.rms)
      end)
      |> then(&%{igniter | rewrite: &1})
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

  @doc "Adds a task to the tasks list. Tasks will be run after all changes have been committed"
  def add_task(igniter, task, argv \\ []) when is_binary(task) do
    %{igniter | tasks: igniter.tasks ++ [{task, argv}]}
  end

  @doc "Adds a delayed task to the tasks list. Delayed tasks will be run after all other composed tasks have been added."
  def delay_task(igniter, task, argv \\ []) when is_binary(task) do
    %{igniter | tasks: igniter.tasks ++ [{task, argv, :delayed}]}
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
        |> Map.put(:task, Mix.Task.task_name(task))
        |> Map.put(:parent, igniter.task)
        |> Igniter.Mix.Task.configure_and_run(task, argv || igniter.args.argv_flags)
        |> Map.put(:parent, igniter.parent)
        |> Map.put(:task, igniter.task)
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

  ## Options

  - `:required?` - Tracks an issue for the file missing. Defaults to `true`.

  """
  @spec update_elixir_file(t(), Path.t(), zipper_updater(), keyword) :: Igniter.t()
  def update_elixir_file(igniter, path, func, opts \\ []) do
    required? = Keyword.get(opts, :required?, true)

    cond do
      Rewrite.has_source?(igniter.rewrite, path) ->
        igniter
        |> apply_func_with_zipper(path, func)
        |> format(path)

      exists?(igniter, path) ->
        source = read_ex_source!(igniter, path)

        %{igniter | rewrite: Rewrite.put!(igniter.rewrite, source)}
        |> format(path)
        |> apply_func_with_zipper(path, func)
        |> format(path)

      required? ->
        add_issue(igniter, "Required #{path} but it did not exist")

      true ->
        igniter
    end
  end

  @doc "Checks if a file exists on the file system or in the igniter."
  @spec exists?(t(), Path.t()) :: boolean()
  def exists?(igniter, path) do
    path = Igniter.Util.BackwardsCompat.relative_to_cwd(path, force: true)

    cond do
      Enum.any?(
        igniter.rms,
        &(&1 == path || subdirectory?(&1, path))
      ) ->
        false

      Rewrite.has_source?(igniter.rewrite, path) ->
        true

      Enum.any?(
        Rewrite.sources(igniter.rewrite),
        &(&1.path == path || subdirectory?(&1.path, path))
      ) ->
        true

      igniter.assigns[:test_mode?] ->
        igniter.assigns[:test_files]
        |> Map.keys()
        |> Enum.any?(&(&1 == path || subdirectory?(&1, path)))

      true ->
        File.exists?(path)
    end
  end

  @doc """
  Updates a given file's `Rewrite.Source`
  """
  @spec update_file(t(), Path.t(), (Rewrite.Source.t() -> Rewrite.Source.t())) :: t()
  def update_file(igniter, path, updater, opts \\ []) do
    path = Igniter.Util.BackwardsCompat.relative_to_cwd(path, force: true)
    source_handler = source_handler(path, opts)

    if Rewrite.has_source?(igniter.rewrite, path) do
      source = Rewrite.source!(igniter.rewrite, path)

      {igniter, source} =
        case updater.(source) do
          {:error, error} ->
            {igniter, Rewrite.Source.add_issues(source, List.wrap(error))}

          {:warning, warning} ->
            {Igniter.add_warning(igniter, warning), source}

          {:notice, notice} ->
            {Igniter.add_notice(igniter, notice), source}

          source ->
            {igniter, source}
        end

      %{igniter | rewrite: Rewrite.update!(igniter.rewrite, source)}
    else
      if exists?(igniter, path) do
        source = read_source!(igniter, path, source_handler)

        {igniter, source} =
          case updater.(source) do
            {:error, error} ->
              {igniter, Rewrite.Source.add_issues(source, List.wrap(error))}

            {:warning, warning} ->
              {Igniter.add_warning(igniter, warning), source}

            {:notice, notice} ->
              {Igniter.add_notice(igniter, notice), source}

            source ->
              {igniter, source}
          end

        %{igniter | rewrite: Rewrite.put!(igniter.rewrite, source)}
        |> maybe_format(path, true, Keyword.put(opts, :source_handler, source_handler))
        |> Map.update!(:rewrite, fn rewrite ->
          source = Rewrite.source!(rewrite, path)
          Rewrite.update!(rewrite, source)
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

  @doc """
  Includes the given file in the project, expecting it to exist. Does nothing if its already been added.

  ## Options

  - `:required?` - Tracks an issue for the file missing. Defaults to `false`.

  """
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
    path = Igniter.Util.BackwardsCompat.relative_to_cwd(path, force: true)

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

      %{igniter | rewrite: Rewrite.put!(igniter.rewrite, source), rms: igniter.rms -- [path]}
      |> maybe_format(path, true, source_handler: source_handler)
    end
  end

  @doc "Creates the given file in the project with the provided string contents, or updates it with a function of type `zipper_updater()` if it already exists."
  @spec create_or_update_elixir_file(t(), Path.t(), String.t(), zipper_updater()) :: Igniter.t()
  def create_or_update_elixir_file(igniter, path, contents, updater) do
    path = Igniter.Util.BackwardsCompat.relative_to_cwd(path, force: true)

    if Rewrite.has_source?(igniter.rewrite, path) do
      igniter
      |> update_elixir_file(path, updater)
    else
      {igniter, created?, source} =
        if path in igniter.rms do
          {%{igniter | rms: igniter.rms -- [path]}, true,
           ""
           |> Rewrite.Source.Ex.from_string(path)
           |> update_source(igniter, :content, contents, by: :file_creator)}
        else
          try do
            {igniter, false, read_ex_source!(igniter, path)}
          rescue
            _ ->
              {igniter, true,
               ""
               |> Rewrite.Source.Ex.from_string(path)
               |> update_source(igniter, :content, contents, by: :file_creator)}
          end
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
    path = Igniter.Util.BackwardsCompat.relative_to_cwd(path, force: true)

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
  Creates a folder in the project.
  """

  @spec mkdir(t(), Path.t()) :: Igniter.t()
  def mkdir(igniter, path) do
    current_dir = Path.expand(".")
    target_path = Path.expand(path)

    if String.starts_with?(target_path, current_dir) do
      %{igniter | mkdirs: [path | igniter.mkdirs]}
    else
      add_issue(igniter, "Igniter.mkdir invalid path: #{path} is outside the current directory.")
    end
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
    path = Igniter.Util.BackwardsCompat.relative_to_cwd(path, force: true)
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
      | rewrite: %{igniter.rewrite | sources: sources},
        rms: igniter.rms -- [path]
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
          |> Igniter.Code.Common.replace_code(clean_comments(zipper.node))
          |> Zipper.topmost()
          |> Zipper.node()

        source = update_source(source, igniter, :quoted, quoted_with_only_deps_change)
        rewrite = Rewrite.update!(igniter.rewrite, source)

        if opts[:force?] || changed?(source) do
          message =
            opts[:message] || "Modify mix.exs and install?"

          if opts[:yes] || opts[:yes_to_deps] || !changed?(source) ||
               diff_and_yes?(igniter, [source], opts, message) do
            rewrite =
              case Rewrite.write(rewrite, "mix.exs", :force) do
                {:ok, rewrite} -> rewrite
                {:error, error} -> raise error
              end

            source = Rewrite.source!(rewrite, "mix.exs")
            source = update_source(source, igniter, :quoted, quoted)

            igniter =
              igniter
              |> Map.update!(:rewrite, &Rewrite.update!(&1, source))
              |> accepted_once()

            if Keyword.get(opts, :fetch?, true) do
              Igniter.Util.Install.get_deps!(
                igniter,
                Keyword.put_new(opts, :operation, "installing new dependencies")
              )
            else
              igniter
            end
          else
            if opts[:error_on_abort?] do
              add_issue(
                igniter,
                "Dependencies fetch was rejected, some installations may not have completed."
              )
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
            "Dependency changes require updating `mix.exs` before continuing.\nModify `mix.exs` and install?"

          if Igniter.Util.IO.yes?(message) do
            rewrite =
              case Rewrite.write(igniter.rewrite, "mix.exs", :force) do
                {:ok, rewrite} -> rewrite
                {:error, error} -> raise error
              end

            igniter =
              Igniter.Util.Install.get_deps!(
                igniter,
                Keyword.put_new(opts, :operation, "installing new dependencies")
              )

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

  defp clean_comments(node) do
    case node do
      {f, meta, a} ->
        {f, Keyword.merge(meta, leading_comments: [], trailing_comments: []), a}

      other ->
        other
    end
  end

  defp diff_and_yes?(igniter, sources, opts, message) do
    display_diff(sources, opts)

    Igniter.Util.IO.yes?(
      message_with_git_warning(
        igniter,
        Keyword.put(opts, :message, message)
      )
    )
  end

  @doc """
  Installs a package as if calling `mix igniter.install`

  See `mix igniter.install` for information on the package format.

  ## Options

  - `append?` - If `true`, appends the package to the existing list of packages instead of prepending. Defaults to `false`.

  ## Examples

    Igniter.install(igniter, "ash")

    Igniter.install(igniter, "ash_authentication@2.0", ["--authentication-strategies", "password,magic_link"])
  """
  def install(igniter, package, argv \\ [], opts \\ []) when is_binary(package) do
    Igniter.Util.Install.install(List.wrap(package), argv, igniter, opts)
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
        Enum.map(paths, &Igniter.Util.BackwardsCompat.relative_to_cwd(&1, force: true))
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
      changed?(source)
    end)
  end

  @doc """
  Executes or dry-runs a given Igniter.
  """
  def do_or_dry_run(igniter, opts \\ []) do
    if igniter.assigns[:test_mode?] do
      raise ArgumentError,
            "Must `Igniter.Test.apply_igniter/1` instead of `Igniter.do_or_dry_run` when running in `test_mode?`."
    end

    igniter = prepare_for_write(igniter)

    title = opts[:title] || "Igniter"

    halt_if_fails_check!(igniter, title, opts)

    case igniter do
      %{issues: []} ->
        result_of_diff_handling =
          if has_changes?(igniter) do
            if opts[:dry_run] || !opts[:yes] do
              Mix.shell().info("\n#{IO.ANSI.green()}#{title}#{IO.ANSI.reset()}:")

              if !opts[:yes] && too_long_to_display?(igniter) do
                handle_long_diff(igniter, opts)
                :no_confirm_dry_run_with_changes
              else
                display_diff(Rewrite.sources(igniter.rewrite), opts)
                :dry_run_with_changes
              end
            end
          else
            if !(opts[:quiet_on_no_changes?] || opts[:yes] ||
                   igniter.assigns[:quiet_on_no_changes?]) do
              Mix.shell().info("\n#{title}:\n\n    No proposed content changes!\n")
            end

            display_notices(igniter)

            :dry_run_with_no_changes
          end

        result_of_dry_run =
          case result_of_diff_handling do
            :no_confirm_dry_run_with_changes ->
              :dry_run_with_changes

            other ->
              other
          end

        display_mkdirs(igniter)

        display_moves(igniter)

        display_rms(igniter)

        display_warnings(igniter, title)

        display_tasks(igniter, result_of_dry_run, opts)

        if opts[:dry_run] ||
             (result_of_diff_handling == :dry_run_with_no_changes &&
                Enum.empty?(igniter.tasks) &&
                Enum.empty?(igniter.moves) && Enum.empty?(igniter.rms)) do
          result_of_dry_run
        else
          if opts[:yes] || result_of_diff_handling == :no_confirm_dry_run_with_changes ||
               Igniter.Util.IO.yes?(message_with_git_warning(igniter, opts)) do
            igniter.rewrite
            |> Enum.any?(fn source ->
              Rewrite.Source.from?(source, :string) || Rewrite.Source.updated?(source)
            end)
            |> Kernel.||(!Enum.empty?(igniter.tasks))
            |> Kernel.||(!Enum.empty?(igniter.moves))
            |> Kernel.||(!Enum.empty?(igniter.rms))
            |> if do
              igniter.rewrite
              |> Rewrite.write_all()
              |> case do
                {:ok, _result} ->
                  if !Enum.empty?(igniter.tasks) do
                    case Enum.at(igniter.tasks, 0) do
                      {"deps.get", []} ->
                        :ok

                      _ ->
                        Mix.shell().cmd("mix deps.get")
                    end
                  end

                  igniter.mkdirs
                  |> Enum.map(&Path.expand(&1, "."))
                  |> Enum.uniq()
                  |> Enum.each(fn path ->
                    File.mkdir_p!(path)
                  end)

                  igniter.moves
                  |> Enum.each(fn {from, to} ->
                    File.mkdir_p!(Path.dirname(to))
                    File.rename!(from, to)
                  end)

                  Enum.each(igniter.rms, fn path ->
                    File.rm!(path)
                  end)

                  igniter.tasks
                  |> sort_tasks_with_delayed_last()
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

  defp accepted_once(igniter) do
    Igniter.assign(
      igniter,
      :private,
      Map.put(igniter.assigns[:private] || %{}, :accepted_once, true)
    )
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

      !Enum.empty?(igniter.moves) ->
        Mix.shell().error("Files would have been removed and the --check flag was specified.")
        display_rms(igniter)

        System.halt(3)

      Igniter.has_changes?(igniter) ->
        Mix.shell().error(
          "Changes have been made to the project and the --check flag was specified."
        )

        display_diff(Rewrite.sources(igniter.rewrite), opts)

        System.halt(1)

      true ->
        :ok
    end
  end

  defp message_with_git_warning(igniter, opts) do
    message = opts[:message] || "Proceed with changes?"

    if opts[:dry_run] || opts[:yes] || igniter.assigns[:test_mode?] || !has_changes?(igniter) do
      message
    else
      if Map.get(igniter.assigns, :prompt_on_git_changes?, true) and
           !igniter.assigns[:private][:accepted_once] do
        case check_git_status() do
          {:dirty, output} ->
            """
            #{IO.ANSI.red()}Warning! Uncommitted git changes detected in the project. #{IO.ANSI.reset()}

            You #{IO.ANSI.yellow()}may#{IO.ANSI.reset()} want to save these changes and rerun this command.
            This ensures that you can run `#{IO.ANSI.red()}git reset#{IO.ANSI.reset()}` to undo the changes.

            Output of `#{IO.ANSI.green()}git status -s --porcelain#{IO.ANSI.reset()}`:

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

  @line_limit 1000

  defp too_long_to_display?(igniter) do
    if igniter.assigns[:test_mode?] do
      false
    else
      Enum.reduce_while(igniter.rewrite, {0, false}, fn source, {count, res} ->
        count = count + Enum.count(String.split(source_diff(source, false), "\n"))

        if count > @line_limit do
          {:halt, {count, true}}
        else
          {:cont, {count, res}}
        end
      end)
      |> elem(1)
    end
  end

  defp handle_long_diff(igniter, opts) do
    files_changed =
      igniter.rewrite
      |> Enum.filter(&changed?/1)
      |> Enum.group_by(&Rewrite.Source.from?(&1, :string))
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map_join("\n\n", fn
        {true, sources} ->
          "Creating: \n\n" <>
            Enum.map_join(sources, "\n", &"  * #{Rewrite.Source.get(&1, :path)}")

        {false, sources} ->
          "Updating: \n\n" <>
            Enum.map_join(sources, "\n", &"  * #{Rewrite.Source.get(&1, :path)}")
      end)

    files_changed =
      if Enum.empty?(igniter.moves) do
        files_changed
      else
        "Moving: \n\n" <>
          (igniter.moves
           |> Enum.sort_by(&elem(&1, 0))
           |> Enum.map_join("\n", fn {from, to} ->
             "#{IO.ANSI.red()} #{from}#{IO.ANSI.reset()}: #{IO.ANSI.green()}#{to}#{IO.ANSI.reset()}"
           end))
      end

    files_changed =
      if Enum.empty?(igniter.rms) do
        files_changed
      else
        "Deleting: \n\n" <>
          (igniter.rms
           |> Enum.sort()
           |> Enum.map_join("\n", fn path ->
             "#{IO.ANSI.red()} #{path}#{IO.ANSI.reset()}"
           end))
      end

    options = [
      write: "Proceed *without* viewing changes. (default)",
      display: "Display the diff inline anyway.",
      patch_file:
        "Write to `.igniter` so you can preview all of the changes, and wait to proceed."
    ]

    Igniter.Util.IO.select(
      "Too many changes to automatically display a full diff (>= #{@line_limit} lines changed).\n" <>
        "The following files will be changed:\n\n" <>
        files_changed <> "\n\nHow would you like to proceed?",
      options,
      display: &elem(&1, 1),
      default: {:write, nil}
    )
    |> elem(0)
    |> case do
      :display ->
        display_diff(Rewrite.sources(igniter.rewrite), opts)
        :ok

      :patch_file ->
        File.write!(
          ".igniter",
          diff(Rewrite.sources(igniter.rewrite), Keyword.put(opts, :color?, false))
        )

        Mix.shell().info(
          "Diff:\n\n#{IO.ANSI.yellow()}View the diff by opening `#{Path.expand(".igniter")}`.#{IO.ANSI.reset()}"
        )

        :ok

      :write ->
        :no_confirm
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

      source_diff(source, color?)
    end)
  end

  defp source_diff(source, color?) do
    cond do
      Rewrite.Source.from?(source, :string) &&
          String.valid?(Rewrite.Source.get(source, :content)) ->
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

      String.valid?(Rewrite.Source.get(source, :content)) ->
        diff = Rewrite.Source.diff(source, color: color?) |> IO.iodata_to_binary()

        if String.trim(diff) != "" do
          """

          Update: #{Rewrite.Source.get(source, :path)}

          #{diff}
          """
        else
          ""
        end

      !String.valid?(Rewrite.Source.get(source, :content)) ->
        """
        Create: #{Rewrite.Source.get(source, :path)}

        (content diff can't be displayed)
        """

      true ->
        ""
    end
  end

  @doc false
  def format(igniter, adding_paths, reevaluate_igniter_config? \\ true) do
    igniter =
      igniter
      |> include_existing_elixir_file("config/config.exs")
      |> include_existing_elixir_file("config/#{Mix.env()}.exs")

    if adding_paths &&
         Enum.any?(List.wrap(adding_paths), &(Path.basename(&1) == ".formatter.exs")) do
      format(igniter, nil, false)
      |> reevaluate_igniter_config(adding_paths, reevaluate_igniter_config?)
    else
      igniter =
        if igniter.assigns[:test_mode?] do
          igniter
        else
          igniter.rewrite
          |> Rewrite.sources()
          |> Stream.map(& &1.path)
          |> Stream.map(&Path.split/1)
          |> Stream.map(&List.first/1)
          # we don't want to be searching for .formatter.exs
          # outside the project
          |> Stream.reject(&String.starts_with?(&1, ".."))
          |> Stream.uniq()
          # we should walk the tree up to each file instead of using **
          |> Stream.flat_map(
            &[Path.join(&1, "**/.formatter.exs"), Path.join(&1, ".formatter.exs")]
          )
          |> Stream.flat_map(&Path.wildcard(&1))
          |> Enum.reduce(igniter, &Igniter.include_existing_file(&2, &1))
        end

      igniter =
        if exists?(igniter, ".formatter.exs") do
          Igniter.include_existing_file(igniter, ".formatter.exs")
        else
          igniter
        end

      rewrite = igniter.rewrite
      dot_formatter = Rewrite.dot_formatter(rewrite)

      rewrite =
        Enum.reduce(Rewrite.sources(rewrite), rewrite, fn source, rewrite ->
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
          |> Sourceror.Zipper.traverse(fn zipper ->
            if Igniter.Code.Function.function_call?(zipper, :import_config, 1) do
              Sourceror.Zipper.replace(zipper, nil)
            else
              zipper
            end
          end)
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
              Sourceror.Zipper.topmost_root(zipper),
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
    if path in igniter.rms do
      raise %File.Error{reason: :enoent, path: path, action: "read file"}
    else
      if igniter.assigns[:test_mode?] do
        if content = igniter.assigns[:test_files][path] do
          source_handler.from_string(content, path: path)
          |> Map.put(:from, :file)
        else
          raise """
          File #{path} not found in test files.

          Available Files:

          #{Enum.map_join(Map.keys(igniter.assigns[:test_files]), "\n", &"  * #{&1}")}
          """
        end
      else
        source_handler.read!(path)
      end
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
    if Rewrite.Source.from?(source, :string) do
      true
    else
      Rewrite.Source.version(source) > 1 and
        Rewrite.Source.get(source, :content, 1) !=
          Rewrite.Source.get(source, :content)
    end
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
      ["* ", :yellow, indent(format_error(error), 2)]
    end)
    |> display_list([title, " - ", :yellow, "Warnings:"])
  end

  @doc false
  def display_notices(igniter) do
    case igniter.notices do
      [] ->
        :ok

      notices ->
        notices
        |> Enum.reverse()
        |> Enum.map(fn notice ->
          ["* ", :green, indent(notice, 2), :reset]
        end)
        |> display_list(["Notices: "])

        Mix.shell().info([
          :yellow,
          "Notices were printed above. Please read them all before continuing!",
          :reset
        ])
    end
  end

  @doc "Deletes a file when the igniter is applied"
  def rm(igniter, path) do
    path = Igniter.Util.BackwardsCompat.relative_to_cwd(path, force: true)

    %{
      igniter
      | rms: Enum.uniq([path | igniter.rms]),
        rewrite: Rewrite.delete(igniter.rewrite, path)
    }
  end

  @doc false
  def display_mkdirs(igniter) do
    igniter.mkdirs
    |> Enum.map(&Path.expand(&1, ""))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(fn path ->
      if not File.exists?(path) do
        [:green, path]
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> display_list("These folders will be created:")
  end

  defp indent(string, count) do
    string
    |> String.split("\n")
    |> Enum.map_join("\n", &(String.duplicate(" ", count) <> &1))
    |> String.trim_leading(" ")
  end

  @doc false
  def display_moves(igniter) do
    igniter.moves
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {from, to} ->
      ["* ", :red, from, :reset, ": ", :green, to]
    end)
    |> display_list("These files will be moved:")
  end

  @doc false
  def display_rms(igniter) do
    igniter.rms
    |> Enum.sort()
    |> Enum.map(fn path ->
      ["* ", :red, path, :reset]
    end)
    |> display_list("These files will be removed:")
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
      |> sort_tasks_with_delayed_last()
      |> Enum.map(fn {task, args} ->
        ["* ", :red, task, " ", :yellow, Enum.intersperse(args, " ")]
      end)
      |> display_list(title)
    end
  end

  @spec display_list(IO.ANSI.ansidata(), IO.ANSI.ansidata()) :: :ok
  defp display_list([], _title), do: :ok

  defp display_list(list, title) do
    title = [IO.ANSI.format(title), "\n\n"]
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

  def subdirectory?(path, base_path) do
    case relative_to(path, base_path) do
      # Same path, not a subdirectory
      ^base_path ->
        false

      relative_path ->
        if String.starts_with?(relative_path, ".") || String.starts_with?(relative_path, "/") do
          # It's a parent path or an absolute path, not a subdirectory
          false
        else
          # It's a relative path within the base path
          true
        end
    end
  end

  defp relative_to(path, cwd, opts \\ []) when is_list(opts) do
    os_type = :os.type() |> elem(0)
    split_path = Path.split(path)
    split_cwd = Path.split(cwd)
    force = Keyword.get(opts, :force, false)

    case {split_absolute?(split_path, os_type), split_absolute?(split_cwd, os_type)} do
      {true, true} ->
        split_path = expand_split(split_path)
        split_cwd = expand_split(split_cwd)

        case force do
          true -> relative_to_forced(split_path, split_cwd, split_path)
          false -> relative_to_unforced(split_path, split_cwd, split_path)
        end

      {false, false} ->
        split_path = expand_relative(split_path, [], [])
        split_cwd = expand_relative(split_cwd, [], [])
        relative_to_forced(split_path, split_cwd, [])

      {_, _} ->
        Path.join(expand_relative(split_path, [], []))
    end
  end

  defp relative_to_unforced(path, path, _original), do: "."

  defp relative_to_unforced([h | t1], [h | t2], original),
    do: relative_to_unforced(t1, t2, original)

  defp relative_to_unforced([_ | _] = l1, [], _original), do: Path.join(l1)
  defp relative_to_unforced(_, _, original), do: Path.join(original)

  defp relative_to_forced(path, path, _original), do: "."
  defp relative_to_forced(["."], _path, _original), do: "."
  defp relative_to_forced(path, ["."], _original), do: Path.join(path)
  defp relative_to_forced([h | t1], [h | t2], original), do: relative_to_forced(t1, t2, original)

  # this should only happen if we have two paths on different drives on windows
  defp relative_to_forced(original, _, original), do: Path.join(original)

  defp relative_to_forced(l1, l2, _original) do
    base = List.duplicate("..", length(l2))
    Path.join(base ++ l1)
  end

  defp expand_relative([".." | t], [_ | acc], up), do: expand_relative(t, acc, up)
  defp expand_relative([".." | t], acc, up), do: expand_relative(t, acc, [".." | up])
  defp expand_relative(["." | t], acc, up), do: expand_relative(t, acc, up)
  defp expand_relative([h | t], acc, up), do: expand_relative(t, [h | acc], up)
  defp expand_relative([], [], []), do: ["."]
  defp expand_relative([], acc, up), do: up ++ :lists.reverse(acc)

  defp expand_split([head | tail]), do: expand_split(tail, [head])
  defp expand_split([".." | t], [_, last | acc]), do: expand_split(t, [last | acc])
  defp expand_split([".." | t], acc), do: expand_split(t, acc)
  defp expand_split(["." | t], acc), do: expand_split(t, acc)
  defp expand_split([h | t], acc), do: expand_split(t, [h | acc])
  defp expand_split([], acc), do: :lists.reverse(acc)

  defp split_absolute?(split, :win32), do: win32_split_absolute?(split)
  defp split_absolute?(split, _), do: match?(["/" | _], split)

  defp win32_split_absolute?(["//" | _]), do: true
  defp win32_split_absolute?([<<_, ":/">> | _]), do: true
  defp win32_split_absolute?(_), do: false

  @doc false
  def sort_tasks_with_delayed_last(tasks) do
    tasks
    |> Enum.split_with(fn
      {_task, _args, :delayed} -> false
      _ -> true
    end)
    |> then(fn {regular_tasks, delayed_tasks} ->
      regular_tasks ++ Enum.map(delayed_tasks, fn {task, args, :delayed} -> {task, args} end)
    end)
  end
end
