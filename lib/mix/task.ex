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
    * `aliases` - A map of aliases to the schema keys.
    * `composes` - A list of tasks that this task might compose.
    * `installs` - A list of dependencies that should be installed before continuing.
    * `adds_deps` - A list of dependencies that should be added to the `mix.exs`, but do not need to be installed before continuing.
    * `extra_args?` - Whether or not to allow extra arguments. This forces all tasks that compose this task to allow extra args as well.

    Your task should *always* use `switches` and not `strict` to validate provided options!
    """

    @global_options [
      switches: [
        dry_run: :boolean,
        yes: :boolean,
        check: :boolean
      ],
      aliases: [
        d: :dry_run,
        y: :yes,
        c: :check
      ]
    ]

    defstruct schema: [],
              aliases: [],
              composes: [],
              installs: [],
              adds_deps: [],
              extra_args?: false

    @type t :: %__MODULE__{
            schema: Keyword.t(),
            aliases: Keyword.t(),
            composes: [String.t()],
            installs: [{atom(), String.t()}],
            adds_deps: [{atom(), String.t()}],
            extra_args?: boolean()
          }

    def global_options, do: @global_options
  end

  @doc """
  Returns an `Igniter.Mix.Task.Info` struct, with information used when running the igniter task.

  This info will be used to validate arguments in composed tasks.

  ## Important Limitations

  * Each task still must parse its own argv in `igniter/2` and *must* ignore any unknown options.
    To accomplish this, use the automatically imported `options!(argv)` macro, which uses the `info/2`
    callback to validate args and return options
  * You cannot use `composes` to list tasks unless they are in your library or in direct dependencies of your library.
    To validate their options, you must include their options in your own option schema.
  """
  @callback info(argv :: list(String.t()), source :: nil | String.t()) ::
              Info.t()
              | nil

  defmacro __using__(_opts) do
    quote do
      use Mix.Task
      @behaviour Igniter.Mix.Task
      import Igniter.Mix.Task, only: [options!: 1]

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
          |> Kernel.||(%Info{})
          |> Map.update!(:schema, &Keyword.merge(&1, global_options[:switches]))
          |> Map.update!(:aliases, &Keyword.merge(&1, global_options[:aliases]))

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
          raise "what"

          Logger.warning("""
          The task #{Mix.Task.task_name(__MODULE__)} is being composed by #{source}, but it does not declare an option schema.
          Therefore, all options will be allowed. Tasks that may be composed should define `info/2`.
          """)
        end

        nil
      end

      defoverridable supports_umbrella?: 0, info: 2
    end
  end

  @spec options!(argv :: term()) :: term() | no_return
  defmacro options!(argv) do
    quote do
      argv = unquote(argv)
      info = info(argv, Mix.Task.task_name(__MODULE__))
      {parsed, _} = OptionParser.parse!(argv, switches: info.schema, aliases: info.aliases)

      parsed
    end
  end
end
