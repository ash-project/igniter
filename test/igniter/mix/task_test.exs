# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Igniter.Mix.TaskTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

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

  test "it delegates --help to mix help" do
    shell = Mix.shell()
    Mix.shell(Mix.Shell.IO)

    try do
      expected =
        capture_io(fn ->
          Mix.Task.run("help", ["igniter.add"])
        end)

      Mix.Task.reenable("help")

      actual = capture_io(fn -> Mix.Tasks.Igniter.Add.run(["--help"]) end)
      assert actual == expected
    after
      Mix.shell(shell)
    end
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
                         options: [
                           task1_option: "task1",
                           task2_option: "task2"
                         ]
                       }}
    end
  end

  describe "composed schema dep merging" do
    # Covers every form in the `Igniter.Mix.Task.Info.dep` type:
    #   {name, version}
    #   {name, opts}
    #   {name, version, opts}

    defmodule Elixir.Mix.Tasks.ParentAddsDepsAllFormats do
      use Igniter.Mix.Task

      def info(_argv, _parent) do
        %Igniter.Mix.Task.Info{
          composes: ["child_adds_deps_all_formats"],
          adds_deps: [
            {:boundary, "~> 0.10", runtime: false},
            {:parent_git_dep, git: "https://example.com/parent.git"},
            {:parent_versioned, "~> 1.0"}
          ]
        }
      end

      def igniter(igniter), do: igniter
    end

    defmodule Elixir.Mix.Tasks.ChildAddsDepsAllFormats do
      use Igniter.Mix.Task

      def info(_argv, _parent) do
        %Igniter.Mix.Task.Info{
          adds_deps: [
            {:cloak, "~> 1.1"},
            {:child_git_dep, git: "https://example.com/child.git"},
            {:child_with_opts, "~> 2.0", only: :test}
          ]
        }
      end

      def igniter(igniter), do: igniter
    end

    defmodule Elixir.Mix.Tasks.ParentInstallsAllFormats do
      use Igniter.Mix.Task

      def info(_argv, _parent) do
        %Igniter.Mix.Task.Info{
          composes: ["child_installs_all_formats"],
          installs: [
            {:boundary, "~> 0.10", runtime: false},
            {:parent_git_install, git: "https://example.com/parent.git"},
            {:parent_versioned_install, "~> 1.0"}
          ]
        }
      end

      def igniter(igniter), do: igniter
    end

    defmodule Elixir.Mix.Tasks.ChildInstallsAllFormats do
      use Igniter.Mix.Task

      def info(_argv, _parent) do
        %Igniter.Mix.Task.Info{
          installs: [
            {:credo, "~> 1.7", only: [:dev, :test]},
            {:child_git_install, git: "https://example.com/child.git"},
            {:child_versioned_install, "~> 2.0"}
          ]
        }
      end

      def igniter(igniter), do: igniter
    end

    setup do
      Elixir.Mix.Task.load_all()
      :ok
    end

    test "adds_deps merges cleanly across every supported mix dep format" do
      Igniter.Util.Info.validate!(
        [],
        Mix.Tasks.ParentAddsDepsAllFormats.info(nil, nil),
        "parent_adds_deps_all_formats"
      )
    end

    test "installs merges cleanly across every supported mix dep format" do
      Igniter.Util.Info.validate!(
        [],
        Mix.Tasks.ParentInstallsAllFormats.info(nil, nil),
        "parent_installs_all_formats"
      )
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

  describe "args_for_group/2" do
    alias Igniter.Util.Info

    test "passes through flags that don't belong to another group" do
      assert Info.args_for_group(["--option", "foo"], "my_group") == ["--option", "foo"]
    end

    test "passes through positional args" do
      assert Info.args_for_group(["positional", "--option", "foo"], "my_group") ==
               ["positional", "--option", "foo"]
    end

    test "strips this group's prefix from --my_group.option" do
      assert Info.args_for_group(["--my_group.option", "foo"], "my_group") ==
               ["--option", "foo"]
    end

    test "strips this group's prefix from --my_group.option=value" do
      assert Info.args_for_group(["--my_group.option=foo"], "my_group") == ["--option=foo"]
    end

    test "strips this group's prefix from short alias -my_group.o" do
      assert Info.args_for_group(["-my_group.o", "foo"], "my_group") == ["-o", "foo"]
    end

    test "drops other-group namespaced flags" do
      assert Info.args_for_group(["--other_group.option", "foo"], "my_group") == ["foo"]
    end

    test "drops other-group namespaced flags with =value" do
      assert Info.args_for_group(["--other_group.option=foo"], "my_group") == []
    end

    test "keeps --key=value when value contains a dot" do
      assert Info.args_for_group(["--out=priv/schema.json"], "my_group") ==
               ["--out=priv/schema.json"]
    end

    test "keeps --key=value when value is a module name with dots" do
      assert Info.args_for_group(["--module=My.App.Mod"], "my_group") == ["--module=My.App.Mod"]
    end

    test "keeps -k=value when value contains a dot" do
      assert Info.args_for_group(["-o=priv/schema.json"], "my_group") == ["-o=priv/schema.json"]
    end

    test "keeps two-arg form regardless of dots in value" do
      assert Info.args_for_group(["--out", "priv/schema.json"], "my_group") ==
               ["--out", "priv/schema.json"]
    end

    test "keeps a flag adjacent to another flag when neither is namespaced" do
      assert Info.args_for_group(["--out=priv/foo.json", "--format=json"], "my_group") ==
               ["--out=priv/foo.json", "--format=json"]
    end

    test "keeps the value of a stripped group prefix even when it contains dots" do
      assert Info.args_for_group(["--my_group.out=priv/foo.json"], "my_group") ==
               ["--out=priv/foo.json"]
    end

    test "returns empty for empty input" do
      assert Info.args_for_group([], "my_group") == []
    end
  end

  describe "schema type coverage with dotted values" do
    defmodule Elixir.Mix.Tasks.AllTypesTask do
      use Igniter.Mix.Task

      def info(_argv, _parent) do
        %Igniter.Mix.Task.Info{
          schema: [
            path: :string,
            module: :string,
            rate: :float,
            port: :integer,
            verbose: :boolean,
            tag: :keep,
            items: :csv
          ],
          aliases: [
            p: :path,
            r: :rate
          ]
        }
      end

      def igniter(igniter) do
        send(self(), {:options, igniter.args.options})
        igniter
      end
    end

    test ":string with dot in value" do
      Mix.Tasks.AllTypesTask.run(["--path=priv/schema.json"])
      assert_received {:options, options}
      assert options[:path] == "priv/schema.json"
    end

    test ":string module name with multiple dots" do
      Mix.Tasks.AllTypesTask.run(["--module=My.App.Mod"])
      assert_received {:options, options}
      assert options[:module] == "My.App.Mod"
    end

    test ":string short alias with dotted value" do
      Mix.Tasks.AllTypesTask.run(["-p=priv/foo.json"])
      assert_received {:options, options}
      assert options[:path] == "priv/foo.json"
    end

    test ":float survives parsing" do
      Mix.Tasks.AllTypesTask.run(["--rate=1.5"])
      assert_received {:options, options}
      assert options[:rate] == 1.5
    end

    test ":float via short alias" do
      Mix.Tasks.AllTypesTask.run(["-r=2.75"])
      assert_received {:options, options}
      assert options[:rate] == 2.75
    end

    test ":integer (no dot, sanity check)" do
      Mix.Tasks.AllTypesTask.run(["--port=8080"])
      assert_received {:options, options}
      assert options[:port] == 8080
    end

    test ":boolean (no value, sanity check)" do
      Mix.Tasks.AllTypesTask.run(["--verbose"])
      assert_received {:options, options}
      assert options[:verbose] == true
    end

    test ":keep accumulates values where some contain dots" do
      Mix.Tasks.AllTypesTask.run(["--tag=plain", "--tag=value.with.dots", "--tag=other"])
      assert_received {:options, options}
      assert options[:tag] == ["plain", "value.with.dots", "other"]
    end

    test ":csv splits while preserving dots inside items" do
      Mix.Tasks.AllTypesTask.run(["--items=a,b.x,c"])
      assert_received {:options, options}
      assert options[:items] == ["a", "b.x", "c"]
    end

    test "mixed types in a single invocation all survive" do
      Mix.Tasks.AllTypesTask.run([
        "--path=priv/schema.json",
        "--rate=0.95",
        "--port=4000",
        "--verbose",
        "--tag=v1.0",
        "--tag=v1.1",
        "--items=foo.json,bar.csv"
      ])

      assert_received {:options, options}
      assert options[:path] == "priv/schema.json"
      assert options[:rate] == 0.95
      assert options[:port] == 4000
      assert options[:verbose] == true
      assert options[:tag] == ["v1.0", "v1.1"]
      assert options[:items] == ["foo.json", "bar.csv"]
    end
  end
end
