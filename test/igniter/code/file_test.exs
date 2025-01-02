defmodule Igniter.Code.FileTest do
  use ExUnit.Case

  test "files will be created if they do not exist" do
    %{rewrite: rewrite} =
      Igniter.new()
      |> Igniter.create_new_file("lib/foo/bar/something.heex", """
      <div>Hello</div>
      """)
      |> Igniter.prepare_for_write()

    assert rewrite
           |> Rewrite.source!("lib/foo/bar/something.heex")
           |> Rewrite.Source.get(:content) == """
           <div>Hello</div>
           """
  end

  test "files will be read if they exist" do
    assert %{rewrite: rewrite} =
             Igniter.new()
             |> Igniter.include_existing_file("README.md", required?: true)

    assert rewrite
           |> Rewrite.source!("README.md")
           |> Rewrite.Source.get(:content) =~ "code generation"
  end

  test "can update file if it exists" do
    assert %{rewrite: rewrite} =
             Igniter.new()
             |> Igniter.include_existing_file("README.md", required?: true)
             |> Igniter.update_file("README.md", fn source ->
               Rewrite.Source.update(source, :content, "Hello Test")
             end)
             |> Igniter.prepare_for_write()

    assert rewrite
           |> Rewrite.source!("README.md")
           |> Rewrite.Source.get(:content) == "Hello Test"
  end

  test "can create folder" do
    assert %{mkdirs: mkdirs} =
             Igniter.new()
             |> Igniter.mkdir("empty_folder")

    assert mkdirs == ["empty_folder"]
  end

  test "can only create folder inside project directory" do
    %{mkdirs: mkdirs} =
      Igniter.new()
      |> Igniter.mkdir("../empty_folder")

    assert mkdirs == []
  end
end
