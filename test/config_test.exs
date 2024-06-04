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
          config :fake, buz: [:blat]
        """)
        |> Igniter.Config.configure("fake.exs", :fake, [:foo, :bar], "baz")

      config_file = Rewrite.source!(rewrite, "config/fake.exs")

      assert Source.get(config_file, :content) == """
             config :fake, foo: [bar: "baz"], buz: [:blat]
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
             config :spark, formatter: ["Ash.Domain": [], "Ash.Resource": []]
             """
    end

    test "it merges with 2 arg version of existing config with a single path item" do
      %{rewrite: rewrite} =
        Igniter.new()
        |> Igniter.create_new_elixir_file("config/fake.exs", """
          config :fake, buz: [:blat]
        """)
        |> Igniter.Config.configure("fake.exs", :fake, [:foo], "baz")

      config_file = Rewrite.source!(rewrite, "config/fake.exs")

      assert Source.get(config_file, :content) == """
             config :fake, foo: "baz", buz: [:blat]
             """
    end

    test "it merges with 3 arg version of existing config" do
      %{rewrite: rewrite} =
        Igniter.new()
        |> Igniter.create_new_elixir_file("config/fake.exs", """
          config :fake, :buz, [:blat]
        """)
        |> Igniter.Config.configure("fake.exs", :fake, [:foo, :bar], "baz")

      config_file = Rewrite.source!(rewrite, "config/fake.exs")

      assert Source.get(config_file, :content) == """
             config :fake, :buz, [:blat]
             config :fake, foo: [bar: "baz"]
             """
    end

    test "it merges with 3 arg version of existing config with a single path item" do
      %{rewrite: rewrite} =
        Igniter.new()
        |> Igniter.create_new_elixir_file("config/fake.exs", """
          config :fake, :buz, [:blat]
        """)
        |> Igniter.Config.configure("fake.exs", :fake, [:foo], "baz")

      config_file = Rewrite.source!(rewrite, "config/fake.exs")

      assert Source.get(config_file, :content) == """
             config :fake, :buz, [:blat]
             config :fake, foo: "baz"
             """
    end

    test "present values can be updated" do
      %{rewrite: rewrite} =
        Igniter.new()
        |> Igniter.create_new_elixir_file("config/fake.exs", """
          config :fake, :buz, [:blat]
        """)
        |> Igniter.Config.configure("fake.exs", :fake, [:buz], "baz", fn list ->
          Igniter.Common.prepend_new_to_list(list, "baz")
        end)

      config_file = Rewrite.source!(rewrite, "config/fake.exs")

      assert Source.get(config_file, :content) == """
             config :fake, :buz, ["baz", :blat]
             """
    end

    test "present values can be updated by updating map keys" do
      %{rewrite: rewrite} =
        Igniter.new()
        |> Igniter.create_new_elixir_file("config/fake.exs", """
          config :fake, foo: %{"a" => ["a", "b"]}
        """)
        |> Igniter.Config.configure("fake.exs", :fake, [:foo], %{"b" => ["c", "d"]}, fn zipper ->
          Igniter.Common.set_map_key(zipper, "b", ["c", "d"], fn zipper ->
            zipper
            |> Igniter.Common.prepend_new_to_list(zipper, "c")
            |> Igniter.Common.prepend_new_to_list(zipper, "d")
          end)
          |> case do
            {:ok, zipper} -> zipper
            _ -> zipper
          end
        end)

      config_file = Rewrite.source!(rewrite, "config/fake.exs")

      assert Source.get(config_file, :content) == """
             config :fake, foo: %{"b" => ["c", "d"], "a" => ["a", "b"]}
             """
    end
  end
end
