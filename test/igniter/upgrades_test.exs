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
end
