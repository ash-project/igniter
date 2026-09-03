# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.Igniter.InstallTest do
  use ExUnit.Case
  use Mimic

  import ExUnit.CaptureIO

  defmodule Elixir.Mix.Tasks.Jason.Install do
    use Igniter.Mix.Task

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      Igniter.create_new_file(igniter, ".jason-installer-ran")
    end
  end

  defmodule Elixir.Mix.Tasks.Rewrite.Install do
    use Igniter.Mix.Task

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      Igniter.create_new_file(igniter, ".rewrite-installer-ran")
    end
  end

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
      |> add_rewrite_dep()
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

    test "runs the installer for a newly added package without prompting" do
      output = install([{:jason, "~> 1.4.5"}])

      assert File.exists?("test_project/.jason-installer-ran")
      refute output =~ "already installed. Run its installer again?"
    end

    test "reruns an existing package's installer when accepted" do
      output = install([rewrite_dep()], [], "y\n")

      assert File.exists?("test_project/.rewrite-installer-ran")
      assert output =~ "Dependency rewrite is already installed. Run its installer again?"
    end

    test "does not rerun an existing package's installer when declined" do
      output = install([rewrite_dep()], [], "n\n")

      refute File.exists?("test_project/.rewrite-installer-ran")
      assert output =~ "Dependency rewrite is already installed. Run its installer again?"
    end

    test "--yes reruns an existing package's installer without prompting" do
      output = install([rewrite_dep()], ["--yes"])

      assert File.exists?("test_project/.rewrite-installer-ran")
      refute output =~ "already installed. Run its installer again?"
    end

    test "--skip-installed does not rerun or prompt for an existing package" do
      for argv <- [["--skip-installed"], ["--yes", "--skip-installed"]] do
        output = install([rewrite_dep()], argv)

        refute File.exists?("test_project/.rewrite-installer-ran")
        refute output =~ "already installed. Run its installer again?"
      end
    end

    test "--skip-installed still runs installers for newly added packages" do
      output = install([rewrite_dep(), {:jason, "~> 1.4.5"}], ["--skip-installed"])

      refute File.exists?("test_project/.rewrite-installer-ran")
      assert File.exists?("test_project/.jason-installer-ran")
      refute output =~ "already installed. Run its installer again?"
    end
  end

  defp add_igniter_dep(contents) do
    String.replace(
      contents,
      "defp deps do\n    [\n",
      "defp deps do\n    [\n      {:igniter, path: \"../\"},\n"
    )
  end

  defp add_rewrite_dep(contents) do
    String.replace(
      contents,
      "defp deps do\n    [\n",
      "defp deps do\n    [\n      #{inspect(rewrite_dep())},\n"
    )
  end

  defp rewrite_dep do
    {:rewrite, "~> 1.1 and >= 1.1.1"}
  end

  defp install(deps, argv, input \\ "") do
    stub(Igniter.Mix.Task, :tty?, fn -> true end)

    capture_io(input, fn ->
      File.cd!("test_project", fn ->
        Igniter.Util.Install.install(deps, argv)
      end)
    end)
  end

  defp cmd!(cmd, args, opts \\ []) do
    {output, status} = System.cmd(cmd, args, opts)
    assert status == 0, "Command failed with exit code #{status}: #{cmd} #{inspect(args)}"

    output
  end
end
