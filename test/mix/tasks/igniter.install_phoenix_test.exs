defmodule Mix.Tasks.Igniter.InstallPhoenixTest do
  use ExUnit.Case
  import Igniter.Test

  test "config_inject" do
    test_project()
    |> Igniter.compose_task("igniter.install_phoenix", ["my_app"])
    |> assert_creates("config/dev.exs")
  end
end
