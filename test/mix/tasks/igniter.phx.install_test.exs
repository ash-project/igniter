# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.Igniter.Phx.InstallTest do
  use ExUnit.Case
  import Igniter.Test

  test "create files" do
    igniter = Igniter.compose_task(test_project(), "igniter.phx.install", ["my_app"])
    assert Enum.count(igniter.rewrite.sources) == 49
  end

  test "inject config" do
    test_project()
    |> Igniter.compose_task("igniter.phx.install", ["my_app"])
    |> assert_has_patch("config/dev.exs", """
    22 | # Configure your database
    23 | config :my_app, MyApp.Repo,
    24 |   username: "postgres",
    25 |   password: "postgres",
    26 |   hostname: "localhost",
    27 |   database: "my_app_dev",
    28 |   stacktrace: true,
    29 |   show_sensitive_data_on_connection_error: true,
    30 |   pool_size: 10
    """)
  end
end
