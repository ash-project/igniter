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

    def igniter(igniter, argv) do
      options = options!(argv)
      {args, _argv} = positional_args!(argv)

      send(self(), {:args, args})
      send(self(), {:options, options})
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
    ExampleTask.igniter(Igniter.new(), ["foo", "--option", "foo"])
    assert_received {:options, options}
    assert options[:option] == "foo"
    assert_received {:args, %{a: "foo"}}
  end

  test "it parses rest options" do
    ExampleTask.igniter(Igniter.new(), ["foo", "--option", "foo"])
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

      def igniter(igniter, _argv) do
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

      def igniter(igniter, _argv) do
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

      def igniter(igniter, _argv) do
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

      def igniter(igniter, _argv) do
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

      def igniter(igniter, argv) do
        {_, argv} = positional_args!(argv)
        send(self(), {:options, options!(argv)})
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
  end
end
