defmodule Igniter.Mix.TaskTest do
  use ExUnit.Case, async: false

  defmodule ExampleTask do
    use Igniter.Mix.Task

    def info(_argv, _parent) do
      %Igniter.Mix.Task.Info{
        schema: [
          option: :string
        ],
        positional: [
          :a,
          b: [
            optional: true,
            rest: true
          ]
        ]
      }
    end

    def igniter(igniter) do
      send(self(), {:args, igniter.args.positional})
      send(self(), {:options, igniter.args.options})
      igniter
    end
  end

  setup do
    current_shell = Mix.shell()

    :ok = Mix.shell(Mix.Shell.Process)

    on_exit(fn ->
      Mix.shell(current_shell)
    end)
  end

  test "it parses options" do
    ExampleTask.run(["foo", "--option", "foo"])
    assert_received {:options, options}
    assert options[:option] == "foo"
    assert_received {:args, %{a: "foo"}}
  end

  test "it parses rest options" do
    ExampleTask.run(["foo", "--option", "foo"])
    assert_received {:options, options}
    assert options[:option] == "foo"
    assert_received {:args, %{a: "foo"}}
  end

  describe "option merging" do
    defmodule Elixir.Mix.Tasks.ExampleTaskGroupA do
      use Igniter.Mix.Task

      def info(_argv, _parent) do
        %Igniter.Mix.Task.Info{
          group: :a,
          schema: [
            option: :string
          ],
          aliases: [
            o: :option
          ],
          composes: [
            "example_task2_group_a"
          ]
        }
      end

      def igniter(igniter) do
        igniter
      end
    end

    defmodule Elixir.Mix.Tasks.ExampleTask2GroupA do
      use Igniter.Mix.Task

      def info(_argv, _parent) do
        %Igniter.Mix.Task.Info{
          group: :a,
          schema: [
            option: :string
          ],
          composes: [
            "example_task_group_b"
          ]
        }
      end

      def igniter(igniter) do
        igniter
      end
    end

    defmodule Elixir.Mix.Tasks.ExampleTaskGroupB do
      use Igniter.Mix.Task

      def info(_argv, _parent) do
        %Igniter.Mix.Task.Info{
          group: :b,
          schema: [
            option: :string
          ]
        }
      end

      def igniter(igniter) do
        igniter
      end
    end

    defmodule Elixir.Mix.Tasks.ExampleTask2GroupB do
      use Igniter.Mix.Task

      def info(_argv, _parent) do
        %Igniter.Mix.Task.Info{
          group: :b,
          schema: [
            option: :string,
            other: :string
          ],
          aliases: [
            o: :other
          ],
          composes: [
            "example_task2_group_a"
          ]
        }
      end

      def igniter(igniter) do
        igniter
      end
    end

    defmodule Elixir.Mix.Tasks.ExampleTask3GroupB do
      use Igniter.Mix.Task

      def info(_argv, _parent) do
        %Igniter.Mix.Task.Info{
          group: :b,
          schema: [
            option: :string,
            other: :string
          ],
          aliases: [
            o: :other
          ],
          composes: [
            "example_task_group_a"
          ]
        }
      end

      def igniter(igniter) do
        send(self(), {:options, igniter.args.options})
        igniter
      end
    end

    defmodule Elixir.Mix.Tasks.ExampleTask1GroupC do
      use Igniter.Mix.Task

      def info(_argv, _parent) do
        %Igniter.Mix.Task.Info{
          group: :c,
          positional: [:task1_positional],
          schema: [
            task1_option: :string
          ],
          composes: [
            "example_task2_group_c"
          ]
        }
      end

      def igniter(igniter) do
        igniter = Igniter.compose_task(igniter, Elixir.Mix.Tasks.ExampleTask2GroupC)
        send(self(), {:task1_group_c, igniter.args})
        igniter
      end
    end

    defmodule Elixir.Mix.Tasks.ExampleTask2GroupC do
      use Igniter.Mix.Task

      def info(_argv, _parent) do
        %Igniter.Mix.Task.Info{
          group: :c,
          schema: [task2_option: :string]
        }
      end

      def igniter(igniter) do
        send(self(), {:task2_group_c, igniter.args})
        igniter
      end
    end

    setup do
      Elixir.Mix.Task.load_all()

      :ok
    end

    test "it succeeds when there are no conflicts" do
      Igniter.Util.Info.compose_install_and_validate!(
        Igniter.new(),
        [],
        Mix.Tasks.ExampleTaskGroupA.info(nil, nil),
        "example_task_group_a",
        []
      )
    end

    test "it raises errors when there are ambiguous flags provided" do
      try do
        Igniter.Util.Info.compose_install_and_validate!(
          Igniter.new(),
          ["--option", "foo"],
          Mix.Tasks.ExampleTask2GroupA.info(nil, nil),
          "example_task2_group_a",
          []
        )

        flunk("was supposed to exit")
      catch
        :exit, {:shutdown, 2} ->
          :ok
      end
    end

    test "it raises errors when there are ambiguous aliases provided" do
      try do
        Igniter.Util.Info.compose_install_and_validate!(
          Igniter.new(),
          ["--option", "foo"],
          Mix.Tasks.ExampleTask2GroupB.info(nil, nil),
          "example_task2_group_b",
          []
        )

        flunk("was supposed to exit")
      catch
        :exit, {:shutdown, 2} ->
          :ok
      end
    end

    test "it uses conflict resolved prefixes to populate options" do
      Mix.Task.run("example_task3_group_b", ["-b.o", "foo"])

      assert_received {:options, options}
      assert options[:other] == "foo"
    end

    test "composed tasks do not consume current task args" do
      Mix.Tasks.ExampleTask1GroupC.run([
        "positional_1",
        "--task1-option",
        "task1",
        "--task2-option",
        "task2"
      ])

      assert_received {:task2_group_c,
                       %{
                         positional: task2_positional,
                         options: [
                           yes: true,
                           task1_option: "task1",
                           task2_option: "task2"
                         ]
                       }}

      assert task2_positional == %{}

      assert_received {:task1_group_c,
                       %{
                         positional: %{
                           task1_positional: "positional_1"
                         },
                         options: [task1_option: "task1", task2_option: "task2"]
                       }}
    end
  end

  describe "parse_argv/1" do
    defmodule ExampleTaskWithOverriddenParseArgv do
      use Igniter.Mix.Task

      def parse_argv(_argv) do
        %Igniter.Mix.Task.Args{
          argv: :overridden
        }
      end

      def igniter(igniter) do
        send(self(), {:args, igniter.args})
        igniter
      end
    end

    test "can be overridden" do
      ExampleTaskWithOverriddenParseArgv.run([])

      assert_received {:args, %Igniter.Mix.Task.Args{argv: :overridden}}
    end
  end

  describe "igniter/2 deprecation" do
    defp define_module do
      original_opts = Code.compiler_options()
      Code.put_compiler_option(:ignore_module_conflict, true)

      {:module, module, _, _} =
        defmodule ExampleTaskWithIgniter1AndIgniter2 do
          use Igniter.Mix.Task

          def info(_argv, _parent) do
            %Igniter.Mix.Task.Info{}
          end

          def igniter(igniter) do
            send(self(), {:igniter1, igniter.args})
            igniter
          end

          def igniter(igniter, _argv) do
            send(self(), :igniter2)
            igniter
          end
        end

      Code.compiler_options(original_opts)

      module
    end

    test "igniter/2 is not called if igniter/1 is defined" do
      ExUnit.CaptureLog.capture_log(fn ->
        task = define_module()
        task.run([])
      end)

      assert_receive {:igniter1, %Igniter.Mix.Task.Args{}}
      refute_receive :igniter2
    end

    test "warning is logged if both igniter/1 and igniter/2 are defined" do
      {module, logged} =
        ExUnit.CaptureLog.with_log(fn ->
          define_module()
        end)

      assert logged =~ inspect(module)
      assert logged =~ "defines both igniter/1 and igniter/2"
    end

    test "compilation error is raised if neither igniter/1 nor igniter/2 are defined" do
      assert_raise CompileError, ~r"must define either igniter/1 or igniter/2", fn ->
        defmodule ShouldRaise do
          use Igniter.Mix.Task
        end
      end
    end
  end
end
