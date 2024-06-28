defmodule Igniter.Mix.Task do
  @moduledoc "A behaviour for implementing a Mix task that is enriched to be composable with other Igniter tasks."

  @doc """
  Whether or not it supports being run in the root of an umbrella project

  At the moment, this is still experimental and we suggest not turning it on.
  """
  @callback supports_umbrella?() :: boolean()
  @doc "All the generator behavior happens here, you take an igniter and task arguments, and return an igniter."
  @callback igniter(igniter :: Igniter.t(), argv :: list(String.t())) :: Igniter.t()
  @doc """
  Returns an option schema and a list of tasks that this task *might* compose *and* pass all argv to.

  The option schema should be in the format you give to `OptionParser`.

  This is callback is used to validate all options up front.

  The following keys can be returned:
  * `schema` - The option schema for this task.
  * `aliases` - A map of aliases to the schema keys.
  * `extra_args?` - Whether or not to allow extra arguments. This forces all tasks that compose this task to allow extra args as well.
  * `composes` - A list of tasks that this task might compose.

  Your task should *always* use `switches` and not `strict` to validate provided options!

  ## Important Limitations

  * Each task still must parse its own argv in `igniter/2` and *must* ignore any unknown options.
  * You cannot use `composes` to list tasks unless they are in your library or in direct dependencies of your library.
    To validate their options, you must include their options in your own option schema.
  """
  @callback option_schema(argv :: list(String.t()), source :: nil | String.t()) ::
              %{
                optional(:schema) => Keyword.t(),
                optional(:aliases) => Keyword.t(),
                optional(:composes) => [String.t()]
              }
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

        schema = option_schema(argv, nil)
        Igniter.Util.Options.validate!(argv, schema, Mix.Task.task_name(__MODULE__))

        Igniter.new()
        |> igniter(argv)
        |> Igniter.do_or_dry_run(argv)
      end

      @impl Igniter.Mix.Task
      def supports_umbrella?, do: false

      @impl Igniter.Mix.Task
      def option_schema(argv, source) do
        require Logger

        if source && source != "igniter.install" do
          Logger.warning("""
          The task #{Mix.Task.task_name(__MODULE__)} is being composed by #{source}, but it does not declare an option schema.
          Therefore, all options will be allowed. Tasks that may be composed should define `option_schema/2`.
          """)
        end

        nil
      end

      defoverridable supports_umbrella?: 0, option_schema: 2
    end
  end
end
