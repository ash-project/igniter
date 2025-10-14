# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs.contributors>
#
# SPDX-License-Identifier: MIT

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

  alias Igniter.Mix.Task.Args
  alias Igniter.Mix.Task.Info

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
    quote generated: true do
      use Mix.Task
      import Igniter.Mix.Task, only: [options!: 1, positional_args!: 1]

      @behaviour Igniter.Mix.Task
      @before_compile Igniter.Mix.Task

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

        if opts[:scribe] do
          Igniter.Test.test_project()
          |> Igniter.assign(:scribe?, true)
        else
          Igniter.new()
        end
        |> Map.put(:task, Mix.Task.task_name(__MODULE__))
        |> Igniter.Mix.Task.configure_and_run(__MODULE__, argv)
        |> then(fn igniter ->
          if opts[:scribe] do
            Igniter.Scribe.write(igniter, opts[:scribe])
          else
            opts = Keyword.put(opts, :yes, igniter.args.options[:yes])
            Igniter.do_or_dry_run(igniter, opts)
          end
        end)
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
        {positional, argv_flags} =
          Igniter.Mix.Task.__positional_args__!(__MODULE__, argv)

        options = Igniter.Mix.Task.__options__!(__MODULE__, argv_flags)
        %Args{positional: positional, options: options, argv: argv, argv_flags: argv_flags}
      end

      defoverridable supports_umbrella?: 0, info: 2, installer?: 0, parse_argv: 1
    end
  end

  defmacro __before_compile__(_env) do
    quote generated: true do
      require Logger

      igniter1_defined? = Module.defines?(__MODULE__, {:igniter, 1}, :def)
      igniter2_defined? = Module.defines?(__MODULE__, {:igniter, 2}, :def)

      if igniter1_defined? and igniter2_defined? do
        Logger.warning("""
        #{inspect(__MODULE__)} (#{__ENV__.file}):

            Module defines both igniter/1 and igniter/2, but igniter/2 is deprecated and will never be called.
        """)
      end

      if not (igniter1_defined? or igniter2_defined?) do
        raise CompileError,
          description:
            "#{inspect(__MODULE__)} must define either igniter/1 or igniter/2 to implement the #{inspect(unquote(__MODULE__))} behaviour"
      end

      if igniter2_defined? do
        Logger.warning("""
        #{inspect(__MODULE__)} (#{__ENV__.file}):

            Module defines `igniter/2`, but `igniter/2` is deprecated.
            Please refactor to `igniter/1`. Use `igniter.args` to access `argv`, `positional` and `options`.
        """)
      end
    end
  end

  if Mix.env() == :test do
    def set_yes(_igniter, args) do
      args
    end
  else
    def set_yes(igniter, args) do
      if !igniter.assigns[:test_mode?] and !Igniter.Mix.Task.tty?() do
        %{args | options: Keyword.put(args.options, :yes, true)}
      else
        args
      end
    end
  end

  @doc false
  def configure_and_run(igniter, task_module, argv) do
    case task_module.parse_argv(argv) do
      %Args{} = args ->
        args = set_yes(igniter, args)

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
  @deprecated "use `igniter.args.options` instead"
  defmacro options!(argv) do
    quote generated: true do
      argv = unquote(argv)
      Igniter.Mix.Task.__options__!(__MODULE__, argv)
    end
  end

  def __options__!(mod, argv) do
    task_name = Mix.Task.task_name(mod)

    info = mod.info(argv, task_name)

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
              |> tap(fn list ->
                last = List.last(list)

                if last && String.ends_with?(last, ",") do
                  arg_name = String.replace(to_string(k), "_", "-")

                  Mix.shell().error("""
                  Found trailing comma in `--#{arg_name}` at `#{last}`

                  Please remove the trailing comma.

                  On some platforms, argument parsing requires quotes around argument values containing commas.
                  So instead of `--#{arg_name} foo,bar`, you may need `--#{arg_name} "foo,bar"`
                  """)

                  exit({:shutdown, 1})
                end
              end)
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
        Mix.shell().error("Missing required flag #{String.replace(to_string(option), "_", "-")} ")

        exit({:shutdown, 1})
      end
    end)

    with_defaults
  end

  @doc false
  # assume we are in a tty if we can't tell
  def tty? do
    case :file.read_file_info("/dev/stdin") do
      {:ok, info} ->
        elem(info, 2) == :device

      _ ->
        true
    end
  rescue
    _ ->
      true
  end

  @deprecated "use `igniter.args.positional` instead"
  defmacro positional_args!(argv) do
    quote generated: true do
      argv = unquote(argv)
      Igniter.Mix.Task.__positional_args__!(__MODULE__, argv)
    end
  end

  def __positional_args__!(mod, argv) do
    task_name = Mix.Task.task_name(mod)
    info = mod.info(argv, task_name)

    argv = Igniter.Util.Info.args_for_group(argv, Igniter.Util.Info.group(info, task_name))

    {argv, positional} = Igniter.Mix.Task.extract_positional_args(argv)

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

  @doc false
  def extract_positional_args(argv) do
    do_extract_positional_args(argv, [], [])
  end

  defp do_extract_positional_args([], argv, positional), do: {argv, positional}

  defp do_extract_positional_args(argv, got_argv, positional) do
    case OptionParser.next(argv, switches: []) do
      {_, _key, true, rest} ->
        do_extract_positional_args(
          rest,
          got_argv ++ [Enum.at(argv, 0)],
          positional
        )

      {_, _key, _value, rest} ->
        count_consumed = Enum.count(argv) - Enum.count(rest)

        do_extract_positional_args(
          rest,
          got_argv ++ Enum.take(argv, count_consumed),
          positional
        )

      {:error, rest} ->
        [first | rest] = rest
        do_extract_positional_args(rest, got_argv, positional ++ [first])
    end
  end
end
