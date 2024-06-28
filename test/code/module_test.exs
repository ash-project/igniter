defmodule Igniter.Code.ModuleTest do
  use ExUnit.Case

  doctest Igniter.Code.Module

  test "modules will be moved according to config" do
    %{rewrite: rewrite} =
      Igniter.new()
      |> Igniter.assign(:igniter_exs,
        leaf_module_location: :inside_folder
      )
      |> Igniter.include_or_create_elixir_file("lib/foo/bar.ex", "defmodule Foo.Bar do\nend")
      |> Igniter.include_or_create_elixir_file(
        "lib/foo/bar/baz.ex",
        "defmodule Foo.Bar.Baz do\nend"
      )
      |> Igniter.prepare_for_write()

    paths = Rewrite.paths(rewrite)

    assert "lib/foo/bar/bar.ex" in paths
    assert "lib/foo/bar/baz.ex" in paths

    #   Igniter.Project.Config.configure(Igniter.new(), "fake.exs", :fake, [:foo, :bar], "baz")

    # config_file = Rewrite.source!(rewrite, "config/fake.exs")

    # assert Source.from?(config_file, :string)

    # assert Source.get(config_file, :content) == """
    #        import Config
    #        config :fake, foo: [bar: "baz"]
    #        """
    # end
  end
end
