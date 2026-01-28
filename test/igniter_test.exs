# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule IgniterTest do
  use ExUnit.Case
  doctest Igniter

  import Igniter.Test
  import ExUnit.CaptureIO

  setup_all do
    ansi_enabled? = Application.get_env(:elixir, :ansi_enabled)
    Application.put_env(:elixir, :ansi_enabled, true)
    on_exit(fn -> Application.put_env(:elixir, :ansi_enabled, ansi_enabled?) end)

    :ok
  end

  describe "Igniter.copy_template/4" do
    test "it evaluates and writes the template" do
      test_project()
      |> Igniter.copy_template("test/templates/template.css.eex", "lib/foobar.css",
        class: "hello"
      )
      |> assert_creates("lib/foobar.css", """
      .hello {
         background: black
      }
      """)
    end

    test "it overwrites an existing file" do
      test_project()
      |> Igniter.copy_template("test/templates/template.css.eex", "lib/foobar.css",
        class: "hello"
      )
      |> apply_igniter!()
      |> Igniter.copy_template(
        "test/templates/template.css.eex",
        "lib/foobar.css",
        [class: "goodbye"],
        on_exists: :overwrite
      )
      |> assert_has_patch("lib/foobar.css", """
      1 - |.hello {
      1 + |.goodbye {
      """)
    end
  end

  describe "diff formatting" do
    test "contains uniform blank lines between diifs" do
      igniter =
        test_project()
        |> Igniter.update_elixir_file("mix.exs", fn zipper ->
          {:ok, Igniter.Code.Common.add_code(zipper, ":ok")}
        end)
        |> Igniter.update_elixir_file("lib/test.ex", fn zipper ->
          {:ok, Igniter.Code.Common.add_code(zipper, ":ok")}
        end)
        |> Igniter.create_new_file("lib/test/example.ex", ":ok\n")
        |> Igniter.create_new_file("lib/test/example2.ex", ":ok\n")

      assert diff(igniter) ==
               """

               Update: lib/test.ex

                    ...|
               18 18   |end
               19 19   |
                  20 + |:ok
                  21 + |


               Create: lib/test/example.ex

               1 |:ok
               2 |


               Create: lib/test/example2.ex

               1 |:ok
               2 |


               Update: mix.exs

                    ...|
               28 28   |end
               29 29   |
                  30 + |:ok
                  31 + |

               """
    end
  end

  describe "display_issues/1" do
    test "prints a list of all added issues" do
      igniter =
        test_project()
        |> Igniter.add_issue("issue 1")
        |> Igniter.add_issue("issue 2")
        |> Igniter.add_issue(%RuntimeError{})

      assert capture_io(fn -> Igniter.display_issues(igniter) end) ==
               """

               \e[31mIssues:\e[0m

               * \e[31missue 1\e[0m
               * \e[31missue 2\e[0m
               * \e[31m** (RuntimeError) runtime error\e[0m

               """
    end

    test "prints nothing if there are no issues" do
      assert capture_io(fn -> Igniter.display_issues(test_project()) end) == ""
    end
  end

  describe "display_warnings/2" do
    test "prints a list of added warnings" do
      igniter =
        test_project()
        |> Igniter.add_warning("warning 1")
        |> Igniter.add_warning("warning 2")
        |> Igniter.add_warning(%RuntimeError{})

      assert capture_io(fn -> Igniter.display_warnings(igniter, "Title") end) ==
               """

               Title - \e[33mWarnings:\e[0m

               * \e[33mwarning 1\e[0m
               * \e[33mwarning 2\e[0m
               * \e[33m** (RuntimeError) runtime error\e[0m

               """
    end

    test "prints nothing if there are no warnings" do
      assert capture_io(fn -> Igniter.display_warnings(test_project(), "Title") end) == ""
    end
  end

  describe "display_notices/1" do
    test "prints a list of added notices" do
      igniter =
        test_project()
        |> Igniter.add_notice("notice 1")
        |> Igniter.add_notice("notice 2")

      assert capture_io(fn -> Igniter.display_notices(igniter) end) ==
               "\nNotices: \n\n* \e[32mnotice 1\e[0m\e[0m\n* \e[32mnotice 2\e[0m\e[0m\n\n\e[33mNotices were printed above. Please read them all before continuing!\e[0m\e[0m\n"
    end

    test "prints nothing if there are no notices" do
      assert capture_io(fn -> Igniter.display_notices(test_project()) end) == ""
    end
  end

  describe "display_moves/1" do
    test "prints a list of added warnings" do
      igniter =
        test_project()
        |> Igniter.move_file("lib/test.ex", "lib/new_test.ex")
        |> Igniter.move_file("test/test_test.exs", "test/new_test_test.exs")

      assert capture_io(fn -> Igniter.display_moves(igniter) end) ==
               """

               These files will be moved:

               * \e[31mlib/test.ex\e[0m: \e[32mlib/new_test.ex\e[0m
               * \e[31mtest/test_test.exs\e[0m: \e[32mtest/new_test_test.exs\e[0m

               """
    end

    test "prints nothing if there are no moves" do
      assert capture_io(fn -> Igniter.display_moves(test_project()) end) == ""
    end
  end

  describe "display_tasks/3" do
    test "prints a list of added tasks" do
      igniter =
        test_project()
        |> Igniter.add_task("task.one")
        |> Igniter.add_task("task.two", ["--opt", "opt"])

      assert capture_io(fn -> Igniter.display_tasks(igniter, :dry_run_with_changes, []) end) ==
               """

               These tasks will be run after the above changes:

               * \e[31mtask.one \e[33m\e[0m
               * \e[31mtask.two \e[33m--opt opt\e[0m

               """
    end

    test "prints nothing if there are no tasks" do
      assert capture_io(fn ->
               Igniter.display_tasks(test_project(), :dry_run_with_changes, [])
             end) ==
               ""
    end

    test "delayed tasks are printed after regular tasks" do
      igniter =
        test_project()
        |> Igniter.add_task("regular.task")
        |> Igniter.delay_task("delayed.task")
        |> Igniter.add_task("another.regular", ["--flag"])
        |> Igniter.delay_task("another.delayed", ["--opt", "value"])

      assert capture_io(fn -> Igniter.display_tasks(igniter, :dry_run_with_changes, []) end) ==
               """

               These tasks will be run after the above changes:

               * \e[31mregular.task \e[33m\e[0m
               * \e[31manother.regular \e[33m--flag\e[0m
               * \e[31mdelayed.task \e[33m\e[0m
               * \e[31manother.delayed \e[33m--opt value\e[0m

               """
    end
  end

  describe "Igniter.new/0" do
    test "does not crash when .formatter.exs is missing (issue #359)" do
      tmp_dir = Path.join(System.tmp_dir!(), "igniter_test_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp_dir)

      try do
        # Create a minimal mix.exs without a .formatter.exs
        File.write!(Path.join(tmp_dir, "mix.exs"), """
        defmodule Test.MixProject do
          use Mix.Project

          def project do
            [
              app: :test,
              version: "0.1.0",
              elixir: "~> 1.17",
              deps: []
            ]
          end
        end
        """)

        File.mkdir_p!(Path.join(tmp_dir, "lib"))

        File.write!(Path.join(tmp_dir, "lib/test.ex"), """
        defmodule Test do
        end
        """)

        # Change to the temp directory and try to create an Igniter
        original_dir = File.cwd!()

        try do
          File.cd!(tmp_dir)

          # This should not raise - it's the bug from issue #359
          igniter = Igniter.new()
          assert %Igniter{} = igniter

          # Also verify we can make and apply changes
          igniter =
            igniter
            |> Igniter.update_elixir_file("lib/test.ex", fn zipper ->
              {:ok, Igniter.Code.Common.add_code(zipper, "def hello, do: :world")}
            end)
            |> Igniter.create_new_file("lib/test/new_file.ex", """
            defmodule Test.NewFile do
              def greet, do: "hello"
            end
            """)

          # Verify the igniter has changes
          assert Igniter.changed?(igniter)

          # Verify we can prepare for write without crashing
          prepared = Igniter.prepare_for_write(igniter)
          assert prepared.issues == []

          # Actually write the files and verify they were written
          assert {:ok, _rewrite} = Rewrite.write_all(prepared.rewrite)

          # Verify the files were written correctly
          assert File.exists?(Path.join(tmp_dir, "lib/test/new_file.ex"))

          updated_test_ex = File.read!(Path.join(tmp_dir, "lib/test.ex"))
          assert updated_test_ex =~ "def hello, do: :world"

          new_file_content = File.read!(Path.join(tmp_dir, "lib/test/new_file.ex"))
          assert new_file_content =~ "defmodule Test.NewFile"
          assert new_file_content =~ "def greet, do: \"hello\""
        after
          File.cd!(original_dir)
        end
      after
        File.rm_rf!(tmp_dir)
      end
    end
  end

  describe "delay_task" do
    test "adds delayed tasks correctly" do
      igniter =
        test_project()
        |> Igniter.add_task("regular.task", ["arg1"])
        |> Igniter.delay_task("delayed.task", ["arg2"])

      assert_has_task(igniter, "regular.task", ["arg1"])
      assert_has_delayed_task(igniter, "delayed.task", ["arg2"])

      # Check that delayed tasks are stored with the :delayed marker
      assert {"delayed.task", ["arg2"], :delayed} in igniter.tasks
      assert {"regular.task", ["arg1"]} in igniter.tasks
    end

    test "delayed tasks are executed after regular tasks" do
      igniter =
        test_project()
        |> Igniter.add_task("first.regular", [])
        |> Igniter.delay_task("first.delayed", [])
        |> Igniter.add_task("second.regular", [])
        |> Igniter.delay_task("second.delayed", [])

      # Test the internal sorting function
      sorted = igniter.tasks |> Igniter.sort_tasks_with_delayed_last()

      assert [
               {"first.regular", []},
               {"second.regular", []},
               {"first.delayed", []},
               {"second.delayed", []}
             ] = sorted
    end
  end
end
