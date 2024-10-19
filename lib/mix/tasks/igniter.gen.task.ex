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
  * `--upgrade` or `-u` - Whether or not the task is an upgrade task. See the upgrades guide for more.
  * `--private` or `-p` - Whether or not the task is a private task. This means it has no shortdoc or moduledoc.
    Upgrade tasks are always private.
  """

  def info(_argv, _source) do
    %Igniter.Mix.Task.Info{
      group: :igniter,
      example: @example,
      positional: [:task_name],
      schema: [optional: :boolean, upgrade: :boolean, private: :boolean],
      aliases: [o: :optional, u: :upgrade, p: :private],
      defaults: [optional: false, upgrade: false, private: false]
    }
  end

  def igniter(igniter, argv) do
    {%{task_name: task_name}, argv} = positional_args!(argv)
    options = options!(argv)

    options =
      if options[:upgrade] do
        Keyword.put(options, :private, true)
      else
        options
      end

    module_name = Module.concat(Mix.Tasks, Mix.Utils.command_to_module_name(to_string(task_name)))

    app_name = Igniter.Project.Application.app_name(igniter)

    contents =
      if options[:optional] do
        optional_template(module_name, task_name, app_name, options)
      else
        template(module_name, task_name, app_name, options)
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

  defp template(module_name, task_name, app_name, opts) do
    docs =
      if opts[:private] do
        "@moduledoc false"
      else
        """
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
        """
      end

    """
    defmodule #{inspect(module_name)} do
      use Igniter.Mix.Task

      @example "mix #{task_name} --example arg"

      #{docs}

      def info(_argv, _composing_task) do
        %Igniter.Mix.Task.Info{
          # Groups allow for overlapping arguments for tasks by the same author
          # See the generators guide for more.
          group: #{inspect(app_name)},
          # dependencies to add
          adds_deps: [],
          # dependencies to add and call their associated installers, if they exist
          installs: [],
          # An example invocation
          example: @example,#{only(opts, task_name)}
          # a list of positional arguments, i.e `[:file]`
          positional: #{positional(opts)},
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

        #{execute(opts, task_name)}
      end
    end
    """
  end

  defp optional_template(module_name, task_name, app_name, opts) do
    docs =
      if opts[:private] do
        "@moduledoc false"
      else
        """
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
        """
      end

    """
    defmodule #{inspect(module_name)} do
      @example "mix #{task_name} --example arg"

      #{docs}

      if Code.ensure_loaded?(Igniter) do
        use Igniter.Mix.Task

        def info(_argv, _composing_task) do
          %Igniter.Mix.Task.Info{
            # Groups allow for overlapping arguments for tasks by the same author
            # See the generators guide for more.
            group: #{inspect(app_name)},
            # dependencies to add
            adds_deps: [],
            # dependencies to add and call their associated installers, if they exist
            installs: [],
            # An example invocation
            example: @example,#{only(opts, task_name)}
            # a list of positional arguments, i.e `[:file]`
            positional: #{positional(opts)},
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

          #{execute(opts, task_name)}
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

  defp only(opts, task_name) do
    if !opts[:upgrade] && String.ends_with?(task_name, ".install") do
      """
      # A list of environments that this should be installed in.
      only: nil,
      """
    else
      ""
    end
  end

  defp execute(opts, task_name) do
    if opts[:upgrade] do
      """
      upgrades = %{
        # "0.1.1" -> [&change_foo_to_bar/2]
      }
      # For each version that requires a change, add it to this map
      # Each key is a version that points at a list of functions that take an
      # igniter and options (i.e flags or other custom options).
      # See the upgrades guide for more.
      Igniter.Upgrades.run(igniter, arguments.from, arguments.to, upgrades, custom_opts: options)
      """
    else
      """
      # Do your work here and return an updated igniter
      igniter
      |> Igniter.add_warning("mix #{task_name} is not yet implemented")
      """
    end
  end

  defp positional(opts) do
    if opts[:upgrade] do
      "[:from, :to]"
    else
      "[]"
    end
  end
end
