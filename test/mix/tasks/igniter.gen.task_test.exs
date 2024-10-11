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

          def info(_argv, _composing_task) do
            %Igniter.Mix.Task.Info{
              # dependencies to add
              adds_deps: [],
              # dependencies to add and call their associated installers, if they exist
              installs: [],
              # An example invocation
              example: @example,
              # Accept additional arguments that are not in your schema
              # Does not guarantee that, when composed, the only options you get are the ones you define
              extra_args?: false,
              # A list of environments that this should be installed in, only relevant if this is an installer.
              only: nil,
              # a list of positional arguments, i.e `[:file]`
              positional: [],
              # Other tasks your task composes using `Igniter.compose_task`, passing in the CLI argv
              # This ensures your option schema includes options from nested tasks
              composes: [],
              # `OptionParser` schema
              schema: [],
              # Default values for the options in the `schema`.
              defaults: [],
              # CLI aliases
              aliases: [],
              # A list of options in the schema that are required
              required: []
            }
          end

          def igniter(igniter, argv) do
            # extract positional arguments according to `positional` above
            {arguments, argv} = positional_args!(argv)
            # extract options according to `schema` and `aliases` above
            options = options!(argv)

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

            def info(_argv, _composing_task) do
              %Igniter.Mix.Task.Info{
                # dependencies to add
                adds_deps: [],
                # dependencies to add and call their associated installers, if they exist
                installs: [],
                # An example invocation
                example: @example,
                # Accept additional arguments that are not in your schema
                # Does not guarantee that, when composed, the only options you get are the ones you define
                extra_args?: false,
                # A list of environments that this should be installed in, only relevant if this is an installer.
                only: nil,
                # a list of positional arguments, i.e `[:file]`
                positional: [],
                # Other tasks your task composes using `Igniter.compose_task`, passing in the CLI argv
                # This ensures your option schema includes options from nested tasks
                composes: [],
                # `OptionParser` schema
                schema: [],
                # Default values for the options in the `schema`.
                defaults: [],
                # CLI aliases
                aliases: [],
                # A list of options in the schema that are required
                required: []
              }
            end

            def igniter(igniter, argv) do
              # extract positional arguments according to `positional` above
              {arguments, argv} = positional_args!(argv)
              # extract options according to `schema` and `aliases` above
              options = options!(argv)

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
  end
end
