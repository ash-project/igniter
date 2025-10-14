# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule Igniter.Mix.Task.Info do
  @moduledoc """
  Info for an `Igniter.Mix.Task`, returned from the `info/2` callback

  ## Configurable Keys

  * `schema` - The option schema for this task, in the format given to `OptionParser`, i.e `[name: :string]`. See the schema section for more.
  * `defaults` - Default values for options in the schema.
  * `required` - A list of flags that are required for this task to run.
  * `positional` - A list of positional arguments that this task accepts. A list of atoms, or a keyword list with the option and config.
    See the positional arguments section for more.
  * `aliases` - A map of aliases to the schema keys.
  * `only` - For installers, a list of environments that the dependency should be installed to.
  * `dep_opts` - For installers, dependency options that should be set, like `runtime: false`. Use the `only` key for `only` option.
  * `composes` - A list of tasks that this task might compose.
  * `installs` - A list of dependencies that should be installed before continuing.
  * `adds_deps` - A list of dependencies that should be added to the `mix.exs`, but do not need to be installed before continuing.
  * `extra_args?` - Whether or not to allow extra arguments. This forces all tasks that compose this task to allow extra args as well.
  * `example` - An example usage of the task. This is used in the help output.

  Your task should *always* use `switches` and not `strict` to validate provided options!

  ## Options and Arguments

  Command line args are automatically parsed into `igniter.args` using this struct's configuration.

      @impl Igniter.Mix.Task
      def igniter(igniter) do
        positional = igniter.args.positional
        options = igniter.args.options
      end

  If you need to do custom validation or parsing, you can implement `c:Igniter.Mix.Task.parse_argv/1`
  and return an `Igniter.Mix.Task.Args` struct. If helpful, the `positional_args!/1` and
  `options!/1` macros can be used to parse positional arguments and options/flags using your
  info configuration.

      @impl Igniter.Mix.Task
      def parse_argv(argv) do
        {positional, argv_flags} = positional_args!(argv)
        options = options!(argv_flags)

        # custom validation or additional parsing

        %Igniter.Mix.Task.Args{
          argv: argv,
          argv_flags: argv_flags,
          positional: positional,
          options: options
        }
      end

  ## Options

  The schema is an option parser schema, and `OptionParser` is used to parse the options, with
  a few notable differences.

  - The defaults from the `defaults` option in your task info are applied.
  - The `:keep` type is automatically aggregated into a list.
  - The `:csv` option automatically splits the value on commas, and allows it to be specified multiple times.
    This also raises an error if an option with a trailing comma is provided, suggesting that the user remove
    the comma or quote the value.

  ## Positional Arguments

  Each positional argument can provide the following options:

  * `:optional` - Whether or not the argument is optional. Defaults to `false`.
  * `:rest` - Whether or not the argument consumes the rest of the positional arguments. Defaults to `false`.
              The value will be converted to a list automatically.
  """

  @global_options [
    switches: [
      dry_run: :boolean,
      yes: :boolean,
      yes_to_deps: :boolean,
      verbose: :boolean,
      only: :keep,
      check: :boolean,
      scribe: :string,
      from_igniter_new: :boolean,
      igniter_repeat: :boolean
    ],
    # no aliases for global options!
    aliases: []
  ]

  defstruct schema: [],
            defaults: [],
            required: [],
            aliases: [],
            group: nil,
            composes: [],
            only: nil,
            dep_opts: [],
            installs: [],
            adds_deps: [],
            positional: [],
            example: nil,
            extra_args?: false,
            # Used internally
            flag_conflicts: %{},
            alias_conflicts: %{}

  @type t :: %__MODULE__{
          schema: Keyword.t(),
          defaults: Keyword.t(),
          required: [atom()],
          aliases: Keyword.t(),
          group: atom | nil,
          composes: [String.t()],
          only: [atom()] | nil,
          dep_opts: Keyword.t(),
          positional: list(atom | {atom, [{:optional, boolean()}, {:rest, boolean()}]}),
          installs: [dep],
          adds_deps: [dep],
          example: String.t() | nil,
          extra_args?: boolean(),
          # used internally
          flag_conflicts: %{optional(atom) => list(String.t())},
          alias_conflicts: %{optional(atom) => list(String.t())}
        }

  @type dep ::
          {atom(), String.t()}
          | {atom(), Keyword.t()}
          | {atom(), String.t(), Keyword.t()}

  def global_options, do: @global_options
end
