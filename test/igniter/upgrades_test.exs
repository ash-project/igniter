# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Igniter.UpgradesTest do
  use ExUnit.Case, async: true

  test "igniter.upgrade parses repeated --except options" do
    options =
      Igniter.Mix.Task.__options__!(
        Mix.Tasks.Igniter.Upgrade,
        ["--all", "--except", "rewrite, glob_ex", "--except", "jason"]
      )

    assert Igniter.Upgrades.except_packages(options) == ["rewrite", "glob_ex", "jason"]
  end

  describe "update_deps/2" do
    test "updates all dependencies without exclusions" do
      assert Igniter.Upgrades.update_deps([], all: true) == [:all]
    end

    test "expands --all --except into the project dependencies minus exclusions" do
      deps = Igniter.Upgrades.update_deps([], all: true, except: ["rewrite,glob_ex"])

      assert "jason" in deps
      refute "rewrite" in deps
      refute "glob_ex" in deps
    end

    test "normalizes repeated except values" do
      deps = Igniter.Upgrades.update_deps([], all: true, except: ["rewrite", "glob_ex"])

      assert "jason" in deps
      refute "rewrite" in deps
      refute "glob_ex" in deps
    end

    test "expands --all --except from dependencies in the requested environment" do
      deps = Igniter.Upgrades.update_deps([], all: true, only: "prod", except: ["rewrite"])

      assert "jason" in deps
      refute "rewrite" in deps
      refute "credo" in deps
    end

    test "normalizes except values with versions" do
      deps = Igniter.Upgrades.update_deps([], all: true, except: ["jason@1.4"])

      refute "jason" in deps
    end

    test "updates explicit dependencies by package name" do
      assert Igniter.Upgrades.update_deps(["jason@1.4", "req"], []) == ["jason", "req"]
    end
  end

  describe "purge_stale_modules/1" do
    @describetag :tmp_dir

    setup %{tmp_dir: tmp_dir} do
      Code.append_path(tmp_dir)

      on_exit(fn ->
        for module <- [__MODULE__.StaleUpgradeTask, __MODULE__.RunningDepModule] do
          :code.purge(module)
          :code.delete(module)
          :code.purge(module)
        end

        Code.delete_path(tmp_dir)
      end)
    end

    test "drops a module loaded from an ebin whose .beam was rebuilt", %{tmp_dir: tmp_dir} do
      module = __MODULE__.StaleUpgradeTask
      {old_binary, new_binary} = compile_versions(module)
      beam = Path.join(tmp_dir, "#{module}.beam")

      # The VM runs the old version, while the dependency's ebin on disk holds the new one.
      {:module, ^module} = :code.load_binary(module, String.to_charlist(beam), old_binary)
      File.write!(beam, new_binary)

      assert apply(module, :version, []) == 1

      Igniter.Upgrades.purge_stale_modules(tmp_dir)

      assert apply(module, :version, []) == 2
    end

    test "leaves a module alone while a process runs its old code", %{tmp_dir: tmp_dir} do
      module = __MODULE__.RunningDepModule
      {old_binary, new_binary} = compile_versions(module)
      beam = String.to_charlist(Path.join(tmp_dir, "#{module}.beam"))

      {:module, ^module} = :code.load_binary(module, beam, old_binary)
      pid = spawn(fn -> apply(module, :wait, []) end)
      ref = Process.monitor(pid)
      # Loading again turns the code the process runs into old code.
      {:module, ^module} = :code.load_binary(module, beam, old_binary)
      File.write!(beam, new_binary)

      Igniter.Upgrades.purge_stale_modules(tmp_dir)

      assert Process.alive?(pid)
      assert apply(module, :version, []) == 1

      send(pid, :stop)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    end
  end

  defp compile_versions(module) do
    compile = fn version ->
      [{^module, binary}] =
        Code.compile_string("""
        defmodule #{inspect(module)} do
          def version, do: #{version}
          def wait, do: receive(do: (:stop -> :ok))
        end
        """)

      :code.purge(module)
      :code.delete(module)
      binary
    end

    {compile.(1), compile.(2)}
  end
end
