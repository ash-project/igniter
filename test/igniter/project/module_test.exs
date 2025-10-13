# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule Igniter.Project.ModuleTest do
  use ExUnit.Case
  import Igniter.Test

  test "module_name_prefix/1" do
    assert Igniter.Project.Module.module_name_prefix(test_project()) == Test
  end
end
