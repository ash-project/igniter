defmodule Igniter.Mix.Task do
  @moduledoc """
  A behaviour for implementing a Mix task that is enriched to be composable with other Igniter tasks.

  > ### Note {: .info}
  >
  > A default `run/1` is implemented so you can directly run the task. Igniter never uses this function, so it is overridable.
  >
  > This enables your library to make use of the task for its own purposes if needed. An example would be if you wanted to implement an Igniter installer, but also have an `install` task for end-user consumption (e.g. `mix tailwind.install`).

  ## Options and Arguments

  Command line args are automatically parsed into `igniter.args` using the configuration returned
  from `c:info/2`. See `Igniter.Mix.Task.Info` for more.
  """

  alias Igniter.Mix.Task.Info
  alias Igniter.Mix.Task.Args

  require Logger

  @doc """
  Whether or not it supports being run in the root of an umbrella project

  At the moment, this is still experimental and we suggest not turning it on.
  """
  @callback supports_umbrella?() :: boolean()

  @doc "Main entrypoint for tasks. This callback accepts and returns an `Igniter` struct."
  @callback igniter(igniter :: Igniter.t()) :: Igniter.t()

  @doc "All the generator behavior happens here, you take an igniter and task arguments, and return an igniter."
  @doc deprecated: "Use igniter/1 instead"
  @callback igniter(igniter :: Igniter.t(), argv :: list(String.t())) :: Igniter.t()

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

  @doc """
  Returns an `Igniter.Mix.Task.Args` struct.

  This callback can be implemented to private custom parsing and validation behavior for
  command line arguments. By default, the options specified in `c:info/2` will be used
  to inject a default implementation.
  """
  @callback parse_argv(argv :: list(String.t())) :: Args.t()

  @callback installer?() :: boolean()

  @optional_callbacks [igniter: 1, igniter: 2]

  defmacro __using__(_opts) do
    quote do
      use Mix.Task
      import Igniter.Mix.Task, only: [options!: 1, positional_args!: 1]

      @behaviour Igniter.Mix.Task
      @after_compile Igniter.Mix.Task

      @impl Mix.Task
      def run(argv) do
        if !supports_umbrella?() && Mix.Project.umbrella?() do
          raise """
          Cannot run #{inspect(__MODULE__)} in an umbrella project.
          """
        end

        if Mix.Task.task_name(__MODULE__) != "igniter.upgrade" do
          Mix.Task.run("compile")
        end

        Application.ensure_all_started(:rewrite)

        global_options = Info.global_options()

        info =
          argv
          |> info(nil)
          |> Map.update!(:schema, &Keyword.merge(&1, global_options[:switches]))

        {opts, _} =
          Igniter.Util.Info.validate!(argv, info, Mix.Task.task_name(__MODULE__))

        Igniter.new()
        |> Igniter.Mix.Task.configure_and_run(__MODULE__, argv)
        |> Igniter.do_or_dry_run(opts)
      end

      defoverridable run: 1

      @impl true
      def installer?, do: __MODULE__ |> Mix.Task.task_name() |> String.ends_with?(".install")

      @impl Igniter.Mix.Task
      def supports_umbrella?, do: false

      @impl Igniter.Mix.Task
      def info(argv, source) do
        %Info{extra_args?: true}
      end

      @impl Igniter.Mix.Task
      def parse_argv(argv) do
        {positional, argv_flags} = positional_args!(argv)
        options = options!(argv_flags)
        %Args{positional: positional, options: options, argv: argv, argv_flags: argv_flags}
      end

      defoverridable supports_umbrella?: 0, info: 2, installer?: 0
    end
  end

  def __after_compile__(env, _bytecode) do
    igniter1_defined? = function_exported?(env.module, :igniter, 1)
    igniter2_defined? = function_exported?(env.module, :igniter, 2)

    if igniter1_defined? and igniter2_defined? do
      Logger.warning("""
      #{inspect(env.module)} (#{env.file})

          Module defines both igniter/1 and igniter/2, but igniter/2 is deprecated and will never be called.
      """)
    end

    if not (igniter1_defined? or igniter2_defined?) do
      raise CompileError,
        description:
          "#{inspect(env.module)} must define either igniter/1 or igniter/2 to implement the #{inspect(__MODULE__)} behaviour"
    end
  end

  @doc false
  def configure_and_run(igniter, task_module, argv) do
    case task_module.parse_argv(argv) do
      %Args{} = args ->
        igniter = %{igniter | args: args}

        if function_exported?(task_module, :igniter, 1) do
          task_module.igniter(igniter)
        else
          task_module.igniter(igniter, argv)
        end

      other ->
        raise """
        Expected #{inspect(task_module)}.parse_argv/2 to return an Igniter.Mix.Task.Args struct,
        but got: #{inspect(other)}
        """
    end
  end

  @doc "Parses the options for the task based on its info."
  @spec options!(argv :: term()) :: term() | no_return
  defmacro options!(argv) do
    quote do
      argv = unquote(argv)

      task_name = Mix.Task.task_name(__MODULE__)

      info = info(argv, task_name)

      argv = Igniter.Util.Info.args_for_group(argv, Igniter.Util.Info.group(info, task_name))

      schema =
        Enum.map(info.schema, fn
          {k, :csv} ->
            {k, :keep}

          {k, v} ->
            {k, v}
        end)

      {parsed, _} = OptionParser.parse!(argv, switches: schema, aliases: info.aliases)

      parsed =
        schema
        |> Enum.filter(fn {_, type} ->
          type == :keep
        end)
        |> Enum.reduce(parsed, fn {k, _}, parsed ->
          parsed_without = Keyword.delete(parsed, k)

          values =
            parsed
            |> Keyword.get_values(k)
            |> List.wrap()

          Keyword.put(parsed_without, k, values)
        end)

      parsed =
        info.schema
        |> Enum.reduce(parsed, fn
          {k, :csv}, parsed ->
            case Keyword.fetch(parsed, k) do
              {:ok, value} ->
                value
                |> List.wrap()
                |> Enum.flat_map(&String.split(&1, ",", trim: true))
                |> then(fn v ->
                  Keyword.put(parsed, k, v)
                end)

              :error ->
                Keyword.put(parsed, k, [])
            end

          {k, :keep}, parsed ->
            Keyword.put_new(parsed, k, [])

          _, parsed ->
            parsed
        end)

      with_defaults = Keyword.merge(info.defaults, parsed)

      Enum.each(info.required, fn option ->
        if !with_defaults[option] do
          Mix.shell().error(
            "Missing required flag #{String.replace(to_string(option), "_", "-")} "
          )

          exit({:shutdown, 1})
        end
      end)

      with_defaults
    end
  end

  defmacro positional_args!(argv) do
    quote do
      argv = unquote(argv)
      task_name = Mix.Task.task_name(__MODULE__)
      info = info(argv, task_name)

      argv = Igniter.Util.Info.args_for_group(argv, Igniter.Util.Info.group(info, task_name))

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

  def consume_args(_, [], got) do
    {[], got}
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

  @doc false
  def igniter_task?(task) when is_atom(task) do
    mix_task? = function_exported?(task, :run, 1)
    igniter_task? = function_exported?(task, :igniter, 1) or function_exported?(task, :igniter, 2)
    mix_task? and igniter_task?
  end
end
