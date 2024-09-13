defmodule Mix.Tasks.Igniter.InstallTest do
  use ExUnit.Case

  setup do
    File.rm_rf!("test_project")
    cmd!("mix", ["new", "test_project"])

    mix_exs = File.read!("test_project/mix.exs")

    new_contents =
      mix_exs
      |> add_igniter_dep()
      |> dont_consolidate_protocols_in_dev()
      |> Code.format_string!()

    File.write!("test_project/mix.exs", new_contents)
    cmd!("mix", ["deps.get"], cd: "test_project")

    on_exit(fn ->
      File.rm_rf!("test_project")
    end)
  end

  describe "installing a new project" do
    test "basic installer works" do
      output = cmd!("mix", ["igniter.install", "jason", "--yes"], cd: "test_project")
      assert String.contains?(output, "The package `jason` had no associated installer task.")
    end

    test "rerunning the same installer lets you know the dependency was not changed" do
      _ = cmd!("mix", ["igniter.install", "jason", "--yes"], cd: "test_project")
      output = cmd!("mix", ["igniter.install", "jason", "--yes"], cd: "test_project")

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

  defp dont_consolidate_protocols_in_dev(contents) do
    String.replace(
      contents,
      "start_permanent: Mix.env() == :prod,\n",
      "start_permanent: Mix.env() == :prod,\n      consolidate_protocols: Mix.env() != :dev,\n"
    )
  end

  defp cmd!(cmd, args, opts \\ []) do
    {output, status} = System.cmd(cmd, args, opts)
    assert status == 0, "Command failed with exit code #{status}: #{cmd} #{inspect(args)}"

    output
  end
end
