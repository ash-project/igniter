defmodule Igniter.TestTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  test "mix_project" do
    assert Map.keys(mix_project().assigns.test_files) |> Enum.sort() == [
             ".formatter.exs",
             ".gitignore",
             ".igniter.exs",
             "README.md",
             "lib/test.ex",
             "mix.exs",
             "test/test_helper.exs",
             "test/test_test.exs"
           ]
  end

  test "phoenix_project(" do
    assert Map.keys(phoenix_project().assigns.test_files) |> Enum.sort() == [
             ".formatter.exs",
             ".gitignore",
             ".igniter.exs",
             "README.md",
             "config/config.exs",
             "config/dev.exs",
             "config/prod.exs",
             "config/runtime.exs",
             "config/test.exs",
             "lib/test.ex",
             "lib/test/application.ex",
             "lib/test_web.ex",
             "lib/test_web/controllers/error_json.ex",
             "lib/test_web/endpoint.ex",
             "lib/test_web/router.ex",
             "lib/test_web/telemetry.ex",
             "mix.exs",
             "test/support/conn_case.ex",
             "test/test_helper.exs",
             "test/test_web/controllers/error_json_test.exs"
           ]
  end
end
