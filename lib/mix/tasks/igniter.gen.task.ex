defmodule Mix.Tasks.Igniter.Gen.Task do
  use Igniter.Mix.Task

  @example "mix igniter.gen.task my_app.install"
  @shortdoc "Generates a new igniter task"

  @moduledoc """
  #{@shortdoc}

  ## Example

  ```bash
  #{@example}
  ```

  ## Options

  * `--optional` or `-o` - Whether or not to define the task to be compatible with igniter as an optional dependency.
  """

  def info(_argv, _source) do
    %Igniter.Mix.Task.Info{
      example: @example,
      positional: [:task_name],
      schema: [optional: :boolean],
      aliases: [o: :optional],
      defaults: [optional: false]
    }
  end

  def igniter(igniter, argv) do
    {%{task_name: task_name}, argv} = positional_args!(argv)
    options = options!(argv)

    module_name = Module.concat(Mix.Tasks, Mix.Utils.command_to_module_name(to_string(task_name)))

    contents =
      if options[:optional] do
        optional_template(module_name, task_name)
      else
        template(module_name, task_name)
      end

    file = "lib/mix/tasks/#{task_name}.ex"

    if Igniter.exists?(igniter, file) do
      Igniter.add_issue(
        igniter,
        "Could not generate task #{task_name}, as `#{file}` already exists."
      )
    else
      Igniter.create_new_file(igniter, file, contents)
    end
  end

  defp template(module_name, task_name) do
    """
    defmodule #{inspect(module_name)} do
      use Igniter.Mix.Task

      @example "mix #{task_name} --example arg"

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
        |> Igniter.add_warning("mix #{task_name} is not yet implemented")
      end
    end
    """
  end

  defp optional_template(module_name, task_name) do
    """
    defmodule #{inspect(module_name)} do
      @example "mix #{task_name} --example arg"

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
          |> Igniter.add_warning("mix #{task_name} is not yet implemented")
        end
      else
        use Mix.Task
        def run(_argv) do
          Mix.shell().error(\"\"\"
          The task '#{task_name}' requires igniter to be run.

          Please install igniter and try again.

          For more information, see: https://hexdocs.pm/igniter
          \"\"\")

          exit({:shutdown, 1})
        end
      end
    end
    """
  end
end
