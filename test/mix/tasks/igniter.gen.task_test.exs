defmodule Mix.Tasks.Igniter.Gen.TaskTest do
  use ExUnit.Case
  import Igniter.Test

  describe "igniter.gen.task" do
    test "generates a mix task" do
      test_project()
      |> Igniter.compose_task("igniter.gen.task", ["foo.bar"])
      |> assert_creates(
        "lib/mix/tasks/foo.bar.ex",
        """
        defmodule Mix.Tasks.Foo.Bar do
          use Igniter.Mix.Task

          @example "mix foo.bar --example arg"

          @shortdoc "A short description of your task"
          @moduledoc \"\"\"
          \#{@shortdoc}

          Longer explanation of your task

          ## Example

          ```bash
          \#{@example}
          ```

          ## Options

          * `--example-option` or `-e` - Docs for your option
          \"\"\"

          @impl Igniter.Mix.Task
          def info(_argv, _composing_task) do
            %Igniter.Mix.Task.Info{
              # Groups allow for overlapping arguments for tasks by the same author
              # See the generators guide for more.
              group: :test,
              # dependencies to add
              adds_deps: [],
              # dependencies to add and call their associated installers, if they exist
              installs: [],
              # An example invocation
              example: @example,
              # a list of positional arguments, i.e `[:file]`
              positional: [],
              # Other tasks your task composes using `Igniter.compose_task`, passing in the CLI argv
              # This ensures your option schema includes options from nested tasks
              composes: [],
              # `OptionParser` schema
              schema: [],
              # Default values for the options in the `schema`
              defaults: [],
              # CLI aliases
              aliases: [],
              # A list of options in the schema that are required
              required: []
            }
          end

          @impl Igniter.Mix.Task
          def igniter(igniter) do
            # Do your work here and return an updated igniter
            igniter
            |> Igniter.add_warning("mix foo.bar is not yet implemented")
          end
        end
        """
      )
    end

    test "generates a mix task that switches on igniter being compiled with `--optional`" do
      test_project()
      |> Igniter.compose_task("igniter.gen.task", ["foo.bar", "--optional"])
      |> assert_creates(
        "lib/mix/tasks/foo.bar.ex",
        """
        defmodule Mix.Tasks.Foo.Bar do
          @example "mix foo.bar --example arg"

          @shortdoc "A short description of your task"
          if !Code.ensure_loaded?(Igniter) do
            @shortdoc "\#{@shortdoc} | Install `igniter` to use"
          end

          @moduledoc \"\"\"
          \#{@shortdoc}

          Longer explanation of your task

          ## Example

          ```bash
          \#{@example}
          ```

          ## Options

          * `--example-option` or `-e` - Docs for your option
          \"\"\"

          if Code.ensure_loaded?(Igniter) do
            use Igniter.Mix.Task

            @impl Igniter.Mix.Task
            def info(_argv, _composing_task) do
              %Igniter.Mix.Task.Info{
                # Groups allow for overlapping arguments for tasks by the same author
                # See the generators guide for more.
                group: :test,
                # dependencies to add
                adds_deps: [],
                # dependencies to add and call their associated installers, if they exist
                installs: [],
                # An example invocation
                example: @example,
                # a list of positional arguments, i.e `[:file]`
                positional: [],
                # Other tasks your task composes using `Igniter.compose_task`, passing in the CLI argv
                # This ensures your option schema includes options from nested tasks
                composes: [],
                # `OptionParser` schema
                schema: [],
                # Default values for the options in the `schema`
                defaults: [],
                # CLI aliases
                aliases: [],
                # A list of options in the schema that are required
                required: []
              }
            end

            @impl Igniter.Mix.Task
            def igniter(igniter) do
              # Do your work here and return an updated igniter
              igniter
              |> Igniter.add_warning("mix foo.bar is not yet implemented")
            end
          else
            use Mix.Task

            def run(_argv) do
              Mix.shell().error(\"\"\"
              The task 'foo.bar' requires igniter to be run.

              Please install igniter and try again.

              For more information, see: https://hexdocs.pm/igniter
              \"\"\")

              exit({:shutdown, 1})
            end
          end
        end
        """
      )
    end

    test "generates an upgrade task" do
      test_project()
      |> Igniter.compose_task("igniter.gen.task", ["foo.bar", "--upgrade"])
      |> assert_creates(
        "lib/mix/tasks/foo.bar.ex",
        """
        defmodule Mix.Tasks.Foo.Bar do
          use Igniter.Mix.Task

          @example "mix foo.bar --example arg"

          @moduledoc false

          @impl Igniter.Mix.Task
          def info(_argv, _composing_task) do
            %Igniter.Mix.Task.Info{
              # Groups allow for overlapping arguments for tasks by the same author
              # See the generators guide for more.
              group: :test,
              # dependencies to add
              adds_deps: [],
              # dependencies to add and call their associated installers, if they exist
              installs: [],
              # An example invocation
              example: @example,
              # a list of positional arguments, i.e `[:file]`
              positional: [:from, :to],
              # Other tasks your task composes using `Igniter.compose_task`, passing in the CLI argv
              # This ensures your option schema includes options from nested tasks
              composes: [],
              # `OptionParser` schema
              schema: [],
              # Default values for the options in the `schema`
              defaults: [],
              # CLI aliases
              aliases: [],
              # A list of options in the schema that are required
              required: []
            }
          end

          @impl Igniter.Mix.Task
          def igniter(igniter) do
            positional = igniter.args.positional
            options = igniter.args.options

            upgrades =
              %{
                # "0.1.1" => [&change_foo_to_bar/2]
              }

            # For each version that requires a change, add it to this map
            # Each key is a version that points at a list of functions that take an
            # igniter and options (i.e. flags or other custom options).
            # See the upgrades guide for more.
            Igniter.Upgrades.run(igniter, positional.from, positional.to, upgrades, custom_opts: options)
          end
        end
        """
      )
    end
  end
end
