defmodule Igniter.ConfigTest do
  use ExUnit.Case

  alias Rewrite.Source

  describe "configure/6" do
    test "it creates the config file if it does not exist" do
      %{rewrite: rewrite} =
        Igniter.Config.configure(Igniter.new(), "fake.exs", :fake, [:foo, :bar], "baz")

      config_file = Rewrite.source!(rewrite, "config/fake.exs")

      assert Source.from?(config_file, :string)

      assert Source.get(config_file, :content) == """
             import Config
             config :fake, foo: [bar: "baz"]
             """
    end

    test "it merges with 2 arg version of existing config" do
      %{rewrite: rewrite} =
        Igniter.new()
        |> Igniter.create_new_elixir_file("config/fake.exs", """
          import Config

          config :fake, buz: [:blat]
        """)
        |> Igniter.Config.configure("fake.exs", :fake, [:foo, :bar], "baz")

      config_file = Rewrite.source!(rewrite, "config/fake.exs")

      assert Source.get(config_file, :content) == """
             import Config

             config :fake, buz: [:blat], foo: [bar: "baz"]
             """
    end

    @tag :regression
    test "it merges the spark formatter plugins" do
      %{rewrite: rewrite} =
        Igniter.new()
        |> Igniter.Config.configure(
          "fake.exs",
          :spark,
          [:formatter, :"Ash.Resource"],
          [],
          fn x ->
            x
          end
        )
        |> Igniter.Config.configure("fake.exs", :spark, [:formatter, :"Ash.Domain"], [], fn x ->
          x
        end)

      config_file = Rewrite.source!(rewrite, "config/fake.exs")

      assert Source.get(config_file, :content) == """
             import Config
             config :spark, formatter: ["Ash.Resource": [], "Ash.Domain": []]
             """
    end

    test "it merges with 2 arg version of existing config with a single path item" do
      %{rewrite: rewrite} =
        Igniter.new()
        |> Igniter.create_new_elixir_file("config/fake.exs", """
          import Config

          config :fake, buz: [:blat]
        """)
        |> Igniter.Config.configure("fake.exs", :fake, [:foo], "baz")

      config_file = Rewrite.source!(rewrite, "config/fake.exs")

      assert Source.get(config_file, :content) == """
             import Config

             config :fake, buz: [:blat], foo: "baz"
             """
    end

    test "it choosees the thre 3 arg version when first item in path is not pretty" do
      %{rewrite: rewrite} =
        Igniter.new()
        |> Igniter.create_new_elixir_file("config/fake.exs", """
          import Config
        """)
        |> Igniter.Config.configure("fake.exs", :fake, [Foo.Bar, :bar], "baz")

      config_file = Rewrite.source!(rewrite, "config/fake.exs")

      assert Source.get(config_file, :content) == """
             import Config
             config :fake, Foo.Bar, bar: "baz"
             """
    end

    test "it choosees the thre 3 arg version when first item in path is not pretty, and merges that way" do
      %{rewrite: rewrite} =
        Igniter.new()
        |> Igniter.create_new_elixir_file("config/fake.exs", """
          import Config
        """)
        |> Igniter.Config.configure("fake.exs", :fake, [Foo.Bar, :bar], "baz")
        |> Igniter.Config.configure("fake.exs", :fake, [Foo.Bar, :buz], "biz")

      config_file = Rewrite.source!(rewrite, "config/fake.exs")

      assert Source.get(config_file, :content) == """
             import Config
             config :fake, Foo.Bar, bar: "baz", buz: "biz"
             """
    end

    test "it merges with 3 arg version of existing config" do
      %{rewrite: rewrite} =
        Igniter.new()
        |> Igniter.create_new_elixir_file("config/fake.exs", """
          import Config

          config :fake, :buz, [:blat]
        """)
        |> Igniter.Config.configure("fake.exs", :fake, [:foo, :bar], "baz")

      config_file = Rewrite.source!(rewrite, "config/fake.exs")

      assert Source.get(config_file, :content) == """
             import Config

             config :fake, foo: [bar: "baz"]
             config :fake, :buz, [:blat]
             """
    end

    test "it merges with 3 arg version of existing config with a single path item" do
      %{rewrite: rewrite} =
        Igniter.new()
        |> Igniter.create_new_elixir_file("config/fake.exs", """
          import Config

          config :fake, :buz, [:blat]
        """)
        |> Igniter.Config.configure("fake.exs", :fake, [:foo], "baz")

      config_file = Rewrite.source!(rewrite, "config/fake.exs")

      assert Source.get(config_file, :content) == """
             import Config

             config :fake, foo: "baz"
             config :fake, :buz, [:blat]
             """
    end

    test "present values can be updated" do
      %{rewrite: rewrite} =
        Igniter.new()
        |> Igniter.create_new_elixir_file("config/fake.exs", """
          import Config

          config :fake, :buz, [:blat]
        """)
        |> Igniter.Config.configure("fake.exs", :fake, [:buz], "baz", fn list ->
          Igniter.Code.List.prepend_new_to_list(list, "baz")
        end)

      config_file = Rewrite.source!(rewrite, "config/fake.exs")

      assert Source.get(config_file, :content) == """
             import Config

             config :fake, :buz, ["baz", :blat]
             """
    end

    test "integers can be used as values" do
      %{rewrite: rewrite} =
        Igniter.new()
        |> Igniter.create_new_elixir_file("config/fake.exs", """
          import Config

          config :fake, :buz, [:blat]
        """)
        |> Igniter.Config.configure("fake.exs", :fake, [:buz], 12)

      config_file = Rewrite.source!(rewrite, "config/fake.exs")

      assert Source.get(config_file, :content) == """
             import Config

             config :fake, :buz, 12
             """
    end

    test "present values can be updated by updating map keys" do
      %{rewrite: rewrite} =
        Igniter.new()
        |> Igniter.create_new_elixir_file("config/fake.exs", """
          import Config

          config :fake, foo: %{"a" => ["a", "b"]}
        """)
        |> Igniter.Config.configure("fake.exs", :fake, [:foo], %{"b" => ["c", "d"]}, fn zipper ->
          Igniter.Code.Map.set_map_key(zipper, "b", ["c", "d"], fn zipper ->
            with {:ok, zipper} <- Igniter.Code.List.prepend_new_to_list(zipper, "c") do
              Igniter.Code.List.prepend_new_to_list(zipper, "d")
            end
          end)
        end)

      config_file = Rewrite.source!(rewrite, "config/fake.exs")

      assert Source.get(config_file, :content) == """
             import Config

             config :fake, foo: %{"a" => ["a", "b"], "b" => ["c", "d"]}
             """
    end
  end
end
