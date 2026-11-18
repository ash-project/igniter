# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.Igniter.InstallTest do
  use ExUnit.Case, async: false
  use Mimic

  import ExUnit.CaptureIO

  setup_all do
    Mimic.copy(Igniter.Mix.Task)
    :ok
  end

  setup :verify_on_exit!

  test "it delegates --help to mix help" do
    expected =
      capture_io(fn ->
        Mix.Task.run("help", ["igniter.install"])
      end)

    Mix.Task.reenable("help")

    actual = capture_io(fn -> Mix.Tasks.Igniter.Install.run(["--help"]) end)
    assert actual == expected
  end

  setup do
    File.rm_rf!("test_project")
    cmd!("mix", ["new", "test_project"])

    mix_exs = File.read!("test_project/mix.exs")

    new_contents =
      mix_exs
      |> add_igniter_dep()
      |> Code.format_string!()

    File.write!("test_project/mix.exs", new_contents)
    cmd!("mix", ["deps.get"], cd: "test_project")

    on_exit(fn ->
      File.rm_rf!("test_project")
    end)
  end

  describe "installing a new project" do
    test "basic installer works" do
      # get the unsuppressed compilation of `test_project`'s deps out of the way,
      # so that the only remaining output is the installer's own
      cmd!("mix", ["deps.compile"], cd: "test_project")
      output = cmd!("mix", ["igniter.install", "jason"], cd: "test_project")

      # each step is reported as a spinner line, with its output suppressed
      assert output =~ "fetching deps"
      refute output =~ "fetching deps:"
      refute output =~ "compiling jason:"
    end

    test "supports setting runtime to false" do
      _ =
        cmd!("mix", ["igniter.install", "jason", "--runtime", "false", "--yes"],
          cd: "test_project"
        )

      assert File.read!("test_project/mix.exs") =~
               ~r/\{:jason, "~> [^"]+", runtime: false\}/
    end

    test "supports setting runtime to true" do
      _ =
        cmd!("mix", ["igniter.install", "jason", "--runtime", "true", "--yes"],
          cd: "test_project"
        )

      assert File.read!("test_project/mix.exs") =~
               ~r/\{:jason, "~> [^"]+", runtime: true\}/
    end

    test "applies the runtime override to every installed package" do
      _ =
        cmd!("mix", ["igniter.install", "jason,decimal", "--runtime", "false", "--yes"],
          cd: "test_project"
        )

      mix_exs = File.read!("test_project/mix.exs")

      assert mix_exs =~ ~r/\{:jason, "~> [^"]+", runtime: false\}/
      assert mix_exs =~ ~r/\{:decimal, "~> [^"]+", runtime: false\}/
    end

    test "rejects a non-boolean runtime value" do
      {output, status} =
        System.cmd("mix", ["igniter.install", "jason", "--runtime", "maybe"],
          cd: "test_project",
          stderr_to_stdout: true
        )

      assert status != 0
      assert output =~ "runtime"
    end

    test "does not report success when installation is declined" do
      mix_exs_before = File.read!("test_project/mix.exs")

      stub(Igniter.Mix.Task, :tty?, fn -> true end)

      output =
        capture_io("n\n", fn ->
          File.cd!("test_project", fn ->
            Igniter.Util.Install.install([{:jason, "~> 1.0"}], [])
          end)
        end)

      mix_exs_after = File.read!("test_project/mix.exs")

      assert mix_exs_after == mix_exs_before
      refute String.contains?(output, "Successfully installed")
    end

    test "displays additional information with `--verbose` option" do
      cmd!("mix", ["deps.compile"], cd: "test_project")
      output = cmd!("mix", ["igniter.install", "jason", "--verbose"], cd: "test_project")

      # each step names itself and passes its output through, rather than spinning.
      # only steps from `Igniter.Util.Install` are asserted on, because the steps
      # before it differ depending on whether the igniter_new archive is installed
      # and intercepts the task
      assert output =~ "fetching deps:"
      assert output =~ "compiling jason:"
    end

    test "rerunning the same installer lets you know the dependency was not changed" do
      _ = cmd!("mix", ["igniter.install", "jason"], cd: "test_project")
      output = cmd!("mix", ["igniter.install", "jason"], cd: "test_project")

      assert String.contains?(
               output,
               "Dependency jason is already in mix.exs with the desired version. Skipping."
             )
    end
  end

  defp add_igniter_dep(contents) do
    String.replace(
      contents,
      "defp deps do\n    [\n",
      "defp deps do\n    [\n      {:igniter, path: \"../\"},\n"
    )
  end

  defp cmd!(cmd, args, opts \\ []) do
    {output, status} = System.cmd(cmd, args, opts)
    assert status == 0, "Command failed with exit code #{status}: #{cmd} #{inspect(args)}"

    output
  end
end
