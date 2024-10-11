defmodule Igniter.Mix.Task.Info do
  @moduledoc """
  Info for an `Igniter.Mix.Task`, returned from the `info/2` callback

  ## Configurable Keys

  * `schema` - The option schema for this task, in the format given to `OptionParser`, i.e `[name: :string]`
  * `defaults` - Default values for options in the schema.
  * `required` - A list of flags that are required for this task to run.
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
            defaults: [],
            required: [],
            aliases: [],
            composes: [],
            only: nil,
            installs: [],
            adds_deps: [],
            positional: [],
            example: nil,
            extra_args?: false

  @type t :: %__MODULE__{
          schema: Keyword.t(),
          defaults: Keyword.t(),
          required: [atom()],
          aliases: Keyword.t(),
          composes: [String.t()],
          only: [atom()] | nil,
          positional: list(atom | {atom, [{:optional, boolean()}, {:rest, boolean()}]}),
          installs: [{atom(), String.t()}],
          adds_deps: [{atom(), String.t()}],
          example: String.t() | nil,
          extra_args?: boolean()
        }

  def global_options, do: @global_options
end
