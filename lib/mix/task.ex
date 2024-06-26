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
  end

  @doc """
  Returns an `Igniter.Mix.Task.Info` struct, with information used when running the igniter task.

  This info will be used to validate arguments in composed tasks.

  ## Important Limitations

  * Each task still must parse its own argv in `igniter/2` and *must* ignore any unknown options.
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

      @impl Mix.Task
      def run(argv) do
        if !supports_umbrella?() && Mix.Project.umbrella?() do
          raise """
          Cannot run #{inspect(__MODULE__)} in an umbrella project.
          """
        end

        Application.ensure_all_started([:rewrite])

        schema = info(argv, nil)
        Igniter.Util.Info.validate!(argv, schema, Mix.Task.task_name(__MODULE__))

        Igniter.new()
        |> igniter(argv)
        |> Igniter.do_or_dry_run(argv)
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

        nil
      end

      defoverridable supports_umbrella?: 0, info: 2
    end
  end
end
