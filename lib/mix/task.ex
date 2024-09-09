defmodule Igniter.Mix.Task do
  @moduledoc "A behaviour for implementing a Mix task that is enriched to be composable with other Igniter tasks."

  @doc """
  Whether or not it supports being run in the root of an umbrella project

  At the moment, this is still experimental and we suggest not turning it on.
  """
  @callback supports_umbrella?() :: boolean()
  @doc "All the generator behavior happens here, you take an igniter and task arguments, and return an igniter."
  @callback igniter(igniter :: Igniter.t(), argv :: list(String.t())) :: Igniter.t()
  defmodule Info do
    @moduledoc """
    Info for an `Igniter.Mix.Task`, returned from the `info/2` callback

    ## Configurable Keys

    * `schema` - The option schema for this task, in the format given to `OptionParser`, i.e `[name: :string]`
    * `positional` - A list of positional arguments that this task accepts. A list of atoms, or a keyword list with the option and config.
      See the positional arguments section for more.
    * `aliases` - A map of aliases to the schema keys.
    * `composes` - A list of tasks that this task might compose.
    * `installs` - A list of dependencies that should be installed before continuing.
    * `adds_deps` - A list of dependencies that should be added to the `mix.exs`, but do not need to be installed before continuing.
    * `extra_args?` - Whether or not to allow extra arguments. This forces all tasks that compose this task to allow extra args as well.
    * `example` - An example usage of the task. This is used in the help output.

    Your task should *always* use `switches` and not `strict` to validate provided options!

    ## Positonal Arguments

    Each positional argument can provide the following options:

    * `:optional` - Whether or not the argument is optional. Defaults to `false`.
    * `:rest` - Whether or not the argument consumes the rest of the positional arguments. Defaults to `false`.
                The value will be converted to a list automatically.

    """

    @global_options [
      switches: [
        dry_run: :boolean,
        yes: :boolean,
        only: :keep,
        check: :boolean
      ],
      # no aliases for global options!
      aliases: []
    ]

    defstruct schema: [],
              aliases: [],
              composes: [],
              only: [],
              installs: [],
              adds_deps: [],
              positional: [],
              example: nil,
              extra_args?: false

    @type t :: %__MODULE__{
            schema: Keyword.t(),
            aliases: Keyword.t(),
            composes: [String.t()],
            only: [atom()],
            positional: list(atom | {atom, [{:optional, boolean()}, {:rest, boolean()}]}),
            installs: [{atom(), String.t()}],
            adds_deps: [{atom(), String.t()}],
            example: String.t() | nil,
            extra_args?: boolean()
          }

    def global_options, do: @global_options
  end

  @doc """
  Returns an `Igniter.Mix.Task.Info` struct, with information used when running the igniter task.

  This info will be used to validate arguments in composed tasks.

  Use the `positional_args!(argv)` to get your positional arguments according to your `info.positional`, and the remaining unused args.
  Use the `options!(argv)` macro to get your parsed options according to your `info.schema`.

  ## Important Limitations

  * Each task still must parse its own argv in `igniter/2` and *must* ignore any unknown options.
    To accomplish this, use the automatically imported `options!(argv)` macro, which uses the `info/2`
    callback to validate args and return options
  * You cannot use `composes` to list tasks unless they are in your library or in direct dependencies of your library.
    To validate their options, you must include their options in your own option schema.
  """
  @callback info(argv :: list(String.t()), composing_task :: nil | String.t()) ::
              Info.t()

  defmacro __using__(_opts) do
    quote do
      use Mix.Task
      @behaviour Igniter.Mix.Task
      import Igniter.Mix.Task, only: [options!: 1, positional_args!: 1]

      @impl Mix.Task
      def run(argv) do
        if !supports_umbrella?() && Mix.Project.umbrella?() do
          raise """
          Cannot run #{inspect(__MODULE__)} in an umbrella project.
          """
        end

        Application.ensure_all_started([:rewrite])

        global_options = Info.global_options()

        info =
          argv
          |> info(nil)
          |> Map.update!(:schema, &Keyword.merge(&1, global_options[:switches]))

        {opts, _} =
          Igniter.Util.Info.validate!(argv, info, Mix.Task.task_name(__MODULE__))

        Igniter.new()
        |> igniter(argv)
        |> Igniter.do_or_dry_run(opts)
      end

      @impl Igniter.Mix.Task
      def supports_umbrella?, do: false

      @impl Igniter.Mix.Task
      def info(argv, source) do
        require Logger

        if source && source != "igniter.install" do
          Logger.warning("""
          The task #{Mix.Task.task_name(__MODULE__)} is being composed by #{source}, but it does not declare an option schema.
          Therefore, all options will be allowed. Tasks that may be composed should define `info/2`.
          """)
        end

        %Info{extra_args?: true}
      end

      defoverridable supports_umbrella?: 0, info: 2
    end
  end

  @doc "Parses the options for the task based on its info."
  @spec options!(argv :: term()) :: term() | no_return
  defmacro options!(argv) do
    quote do
      argv = unquote(argv)

      task_name = Mix.Task.task_name(__MODULE__)

      info = info(argv, task_name)
      {parsed, _} = OptionParser.parse!(argv, switches: info.schema, aliases: info.aliases)
      parsed
    end
  end

  defmacro positional_args!(argv) do
    quote do
      argv = unquote(argv)
      task_name = Mix.Task.task_name(__MODULE__)
      info = info(argv, task_name)

      {argv, positional} = Installer.Lib.Private.SharedUtils.extract_positional_args(argv)

      desired =
        Enum.map(info.positional, fn
          value when is_atom(value) ->
            {value, []}

          other ->
            other
        end)

      {remaining_desired, got} =
        Igniter.Mix.Task.consume_args(positional, desired)

      case Enum.find(remaining_desired, fn {_arg, config} -> !config[:optional] end) do
        {name, config} ->
          line =
            if config[:rest] do
              "Must provide one or more values for positional argument `#{name}`"
            else
              "Required positional argument `#{name}` was not supplied."
            end

          raise ArgumentError, """
          #{line}

          Command: `#{Igniter.Mix.Task.call_structure(task_name, desired)}`
          #{Igniter.Mix.Task.call_example(info)}

          Run `mix help #{task_name}` for more information.
          """

        _ ->
          {Igniter.Mix.Task.add_default_values(Map.new(got), desired), argv}
      end
    end
  end

  @doc false
  def add_default_values(got, desired) do
    Enum.reduce(desired, got, fn {name, config}, acc ->
      if config[:optional] do
        if config[:rest] do
          Map.update(got, name, [], &List.wrap/1)
        else
          Map.put_new(got, name, nil)
        end
      else
        acc
      end
    end)
  end

  @doc false
  def consume_args(positional, desired, got \\ [])

  def consume_args([], desired, got) do
    {desired, got}
  end

  def consume_args([arg | positional], desired, got) do
    {name, config} =
      Enum.find(desired, fn {_name, config} ->
        !config[:optional]
      end) || Enum.at(desired, 0)

    desired = Keyword.delete(desired, name)

    if config[:rest] do
      {desired, Keyword.put(got, name, [arg | positional])}
    else
      consume_args(positional, desired, Keyword.put(got, name, arg))
    end
  end

  @doc false
  def call_example(info) do
    if info.example do
      """

      Example:

      #{indent(info.example)}
      """
    end
  end

  defp indent(example) do
    example
    |> String.split("\n")
    |> Enum.map_join("\n", &"    #{&1}")
  end

  @doc false
  def call_structure(name, desired) do
    call =
      Enum.map_join(desired, " ", fn {name, config} ->
        with_optional =
          if config[:optional] do
            "[#{name}]"
          else
            to_string(name)
          end

        if config[:rest] do
          with_optional <> "[...]"
        else
          with_optional
        end
      end)

    "mix #{name} #{call}"
  end
end
