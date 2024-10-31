defmodule Mix.Tasks.Igniter.UpgradeIgniterTest do
  use ExUnit.Case
  import Igniter.Test

  describe "igniter/2 -> igniter/1 upgrade" do
    test "does not affect non-Igniter.Mix.Task modules" do
      test_project(
        files: %{
          "lib/mix/tasks/my_task.ex" => """
          defmodule Mix.Tasks.MyTask do
            use Mix.Task

            def igniter(igniter, _argv) do
              igniter
            end

            def run(_argv) do
              :ok
            end
          end
          """
        }
      )
      |> Igniter.compose_task("igniter.upgrade_igniter", ["0.3.76", "0.4.0"])
      |> assert_unchanged("lib/mix/tasks/my_task.ex")
    end
  end

  test "upgrades igniter/2 when argv is ignored" do
    test_project(
      files: %{
        "lib/mix/tasks/my_task.ex" => """
        defmodule Mix.Tasks.MyTask do
          use Igniter.Mix.Task

          def igniter(igniter, _argv) do
            igniter
          end
        end
        """
      }
    )
    |> Igniter.compose_task("igniter.upgrade_igniter", ["0.3.76", "0.4.0"])
    |> assert_has_patch("lib/mix/tasks/my_task.ex", """
    - |  def igniter(igniter, _argv) do
    + |  def igniter(igniter) do
    """)
  end

  test "upgrades igniter/2 when argv is used as generated" do
    test_project(
      files: %{
        "lib/mix/tasks/my_task.ex" => """
        defmodule Mix.Tasks.MyTask do
          use Igniter.Mix.Task

          def igniter(igniter, argv) do
            # extract positional arguments according to `positional` above
            {arguments, argv} = positional_args!(argv)
            # extract options according to `schema` and `aliases` above
            options = options!(argv)

            igniter
          end
        end
        """
      }
    )
    |> Igniter.compose_task("igniter.upgrade_igniter", ["0.3.76", "0.4.0"])
    |> assert_has_patch("lib/mix/tasks/my_task.ex", """
    - |  def igniter(igniter, argv) do
    - |    # extract positional arguments according to `positional` above
    - |    {arguments, argv} = positional_args!(argv)
    - |    # extract options according to `schema` and `aliases` above
    - |    options = options!(argv)
    + |  def igniter(igniter) do
    + |    arguments = igniter.args.positional
    + |    options = igniter.args.options
    + |    argv = igniter.args.argv_flags
      |
      |    igniter
    """)
  end
end
