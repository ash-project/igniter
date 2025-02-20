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
      cmd!("mix", ["deps.compile"], cd: "test_project")
      output = cmd!("mix", ["igniter.install", "jason", "--yes"], cd: "test_project")
      refute String.contains?(output, "jason\nCompiling")
      assert String.contains?(output, "Successfully installed:\n\n* jason")
    end

    test "displays additional information with `--verbose` option" do
      output = cmd!("mix", ["igniter.install", "jason", "--yes", "--verbose"], cd: "test_project")
      assert String.contains?(output, "jason\nCompiling")
    end

    test "rerunning the same installer lets you know the dependency was not changed" do
      _ = cmd!("mix", ["igniter.install", "jason", "--yes"], cd: "test_project")
      output = cmd!("mix", ["igniter.install", "jason", "--yes"], cd: "test_project")

      assert String.contains?(
               output,
               "Dependency jason is already in mix.exs with the desired version. Skipping."
             )
    end

    test "support fragment style options" do
      cmd!("mix", ["deps.compile"], cd: "test_project")
      cmd!("mix", ["igniter.install", "poison#runtime=false", "--yes"], cd: "test_project")

      dep_line =
        "./test_project/mix.exs"
        |> File.read!()
        |> String.split("\n")
        |> Enum.find(&String.contains?(&1, ":poison"))

      assert dep_line =~ "runtime: false"
    end

    test "support many fragment style options" do
      cmd!("mix", ["deps.compile"], cd: "test_project")

      opts =
        %{
          app: "false",
          env: :prod,
          compile: "rebar",
          # skipping only as it has special handling
          # only: "[:prod]",
          targets: "[:rpi4, :rpi5]",
          override: true,
          manager: :mix,
          runtime: "false",
          system_env: "%{\"FUN\" => \"true\", \"DULL\" => \"false\"}",
          nerves: "[compile: true]",
          other: true
        }
        |> URI.encode_query()

      cmd!("mix", ["igniter.install", "poison##{opts}", "--yes"], cd: "test_project")

      dep_block =
        "./test_project/mix.exs"
        |> File.read!()
        |> String.split(":poison, ", parts: 2)
        |> Enum.at(1)

      assert dep_block =~ "app: false"
      assert dep_block =~ "env: :prod"
      assert dep_block =~ "compile: \"rebar\""
      # skipping only as it has special handling
      # assert dep_block =~ "only: [:prod]"
      assert dep_block =~ "targets: [:rpi4, :rpi5]"
      assert dep_block =~ "override: true"
      assert dep_block =~ "manager: :mix"
      assert dep_block =~ "runtime: false"
      assert dep_block =~ "system_env: %{\"FUN\" => \"true\", \"DULL\" => \"false\"}"
      assert dep_block =~ "nerves: [compile: true]"
      assert dep_block =~ "other: true"
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

    if status > 0 do
      IO.puts(output)
    end

    assert status == 0, "Command failed with exit code #{status}: #{cmd} #{inspect(args)}"

    output
  end
end
