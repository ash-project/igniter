# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.Igniter.Gen.Task do
  use Igniter.Mix.Task

  @example "mix igniter.gen.task my_app.install"
  @shortdoc "Generates a new igniter task"

  @moduledoc """
  #{@shortdoc}

  ## Example

  ```sh
  #{@example}
  ```

  ## Options

  * `--no-optional` or `-o` - Whether or not to define the task to be compatible with igniter as an optional dependency.
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
      defaults: [optional: true, upgrade: false, private: false]
    }
  end

  def igniter(igniter) do
    task_name = igniter.args.positional.task_name
    options = igniter.args.options

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

    test_contents =
      """
      defmodule #{inspect(module_name)}Test do
        use ExUnit.Case, async: true
        import Igniter.Test

        test "it warns when run" do
          # generate a test project
          test_project()
          # run our task
          |> Igniter.compose_task(\"#{task_name}\", [])
          # see tools in `Igniter.Test` for available assertions & helpers
          |> assert_has_warning("mix #{task_name} is not yet implemented")
        end
      end
      """

    file = "lib/mix/tasks/#{task_name}.ex"
    test_file = "test/mix/tasks/#{task_name}_test.exs"

    if Igniter.exists?(igniter, file) do
      Igniter.add_issue(
        igniter,
        "Could not generate task #{task_name}, as `#{file}` already exists."
      )
    else
      igniter
      |> Igniter.create_new_file(file, contents)
      |> Igniter.create_new_file(test_file, test_contents)
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

        ```sh
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

      @impl Igniter.Mix.Task
      def info(_argv, _composing_task) do
        %Igniter.Mix.Task.Info{
          # Groups allow for overlapping arguments for tasks by the same author
          # See the generators guide for more.
          group: #{inspect(app_name)},
          # *other* dependencies to add
          # i.e `{:foo, "~> 2.0"}`
          adds_deps: [],
          # *other* dependencies to add and call their associated installers, if they exist
          # i.e `{:foo, "~> 2.0"}`
          installs: [],
          # An example invocation
          example: @example,
          #{only(opts, task_name)}\
          # a list of positional arguments, i.e `[:file]`
          positional: #{positional(opts)},
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
        #{execute(opts, task_name)}
      end
    end
    """
  end

  defp docs_module(module_name, task_name, opts) do
    if opts[:private] do
      ""
    else
      """
      defmodule #{inspect(module_name)}.Docs do
        @moduledoc false

        @spec short_doc() :: String.t()
        def short_doc do
          "A short description of your task"
        end

        @spec example() :: String.t()
        def example do
          "mix #{task_name} --example arg"
        end

        @spec long_doc() :: String.t()
        def long_doc do
          \"\"\"
          \#{short_doc()}

          Longer explanation of your task

          ## Example

          ```sh
          \#{example()}
          ```

          ## Options

          * `--example-option` or `-e` - Docs for your option
          \"\"\"
        end
      end
      """
    end
  end

  defp optional_template(module_name, task_name, app_name, opts) do
    """
    #{docs_module(module_name, task_name, opts)}
    if Code.ensure_loaded?(Igniter) do
      defmodule #{inspect(module_name)} do
        #{optional_docs(opts, :present)}

        use Igniter.Mix.Task

        @impl Igniter.Mix.Task
        def info(_argv, _composing_task) do
          %Igniter.Mix.Task.Info{
            # Groups allow for overlapping arguments for tasks by the same author
            # See the generators guide for more.
            group: #{inspect(app_name)},
            # *other* dependencies to add
            # i.e `{:foo, "~> 2.0"}`
            adds_deps: [],
            # *other* dependencies to add and call their associated installers, if they exist
            # i.e `{:foo, "~> 2.0"}`
            installs: [],
            #{example(opts, task_name)}\
            #{only(opts, task_name)}\
            # a list of positional arguments, i.e `[:file]`
            positional: #{positional(opts)},
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
          #{execute(opts, task_name)}
        end
      end
    else
      defmodule #{inspect(module_name)} do
        #{optional_docs(opts, :missing)}

        use Mix.Task

        @impl Mix.Task
        def run(_argv) do
          Mix.shell().error(\"\"\"
          The task '#{task_name}' requires igniter. Please install igniter and try again.

          For more information, see: https://hexdocs.pm/igniter/readme.html#installation
          \"\"\")

          exit({:shutdown, 1})
        end
      end
    end
    """
  end

  defp optional_docs(opts, location) do
    if opts[:private] do
      "@moduledoc false"
    else
      install_igniter =
        if location == :missing do
          " | Install `igniter` to use"
        else
          ""
        end

      """
      @shortdoc "\#{__MODULE__.Docs.short_doc()}#{install_igniter}"

      @moduledoc __MODULE__.Docs.long_doc()
      """
    end
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

  defp example(opts, _task_name) do
    if opts[:private] do
      ""
    else
      """
      # An example invocation
      example: __MODULE__.Docs.example(),
      """
    end
  end

  defp execute(opts, task_name) do
    if opts[:upgrade] do
      """
      positional = igniter.args.positional
      options = igniter.args.options

      upgrades = %{
        # "0.1.1" => [&change_foo_to_bar/2]
      }
      # For each version that requires a change, add it to this map
      # Each key is a version that points at a list of functions that take an
      # igniter and options (i.e. flags or other custom options).
      # See the upgrades guide for more.
      Igniter.Upgrades.run(igniter, positional.from, positional.to, upgrades, custom_opts: options)
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
