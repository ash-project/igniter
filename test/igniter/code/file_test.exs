defmodule Igniter.Code.FileTest do
  use ExUnit.Case

  test "files will be created if they do not exist, in the conventional place, which can be configured" do
    %{rewrite: rewrite} =
      Igniter.new()
      |> Igniter.assign(:igniter_exs,
        module_location: :inside_matching_folder
      )
      |> Igniter.create_new_file("lib/foo/bar/something.heex", """
      <div>Hello</div>
      """)
      |> Igniter.prepare_for_write()

    contents =
      rewrite
      |> Rewrite.source!("lib/foo/bar/something.heex")
      |> Rewrite.Source.get(:content)

    assert contents == """
      <div>Hello</div>
      """
  end
end
