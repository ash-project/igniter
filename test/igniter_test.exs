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
               """

               \e[32mNotice: \e[0mnotice 1\e[0m
               \e[32mNotice: \e[0mnotice 2\e[0m

               """
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

               \e[31mlib/test.ex\e[0m: \e[32mlib/new_test.ex\e[0m
               \e[31mtest/test_test.exs\e[0m: \e[32mtest/new_test_test.exs\e[0m

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
  end
end
