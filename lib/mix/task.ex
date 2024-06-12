defmodule Igniter.Mix.Task do
  @moduledoc "A behaviour for implementing a Mix task that is enriched to be composable with other Igniter tasks."
  @doc """
  Whether or not it supports being run in the root of an umbrella project

  At the moment, this is still experimental and we suggest not turning it on.
  """
  @callback supports_umbrella?() :: boolean()
  @doc "All the generator behavior happens here, you take an igniter and task arguments, and return an igniter."
  @callback igniter(igniter :: Igniter.t(), argv :: list(String.t())) :: Igniter.t()

  defmacro __using__(_opts) do
    quote do
      use Mix.Task
      @behaviour Igniter.Mix.Task

      def run(argv) do
        if !supports_umbrella?() && Mix.Project.umbrella?() do
          raise """
          Cannot run #{inspect(__MODULE__)} in an umbrella project.
          """
        end

        Application.ensure_all_started([:rewrite])

        Igniter.new()
        |> igniter(argv)
        |> Igniter.do_or_dry_run(argv)
      end

      def supports_umbrella?, do: false

      defoverridable supports_umbrella?: 0
    end
  end
end
