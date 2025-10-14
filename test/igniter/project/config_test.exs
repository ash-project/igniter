# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule Igniter.Project.ConfigTest do
  use ExUnit.Case

  import Igniter.Test

  describe "configure/6" do
    test "it creates the config file if it does not exist" do
      test_project()
      |> Igniter.Project.Config.configure("fake.exs", :fake, [:foo, :bar], "baz")
      |> assert_creates("config/fake.exs", """
      import Config
      config :fake, foo: [bar: "baz"]
      """)
    end

    test "it doesn't modify a file if the updater returns an error" do
      igniter =
        test_project(
          files: %{
            "config/config.exs" => """
            import Config

            config :my_app,
              foo: [
                bar: :baz
              ]
            """
          }
        )

      if Igniter.Project.Config.configures_key?(igniter, "config.exs", :my_app, :foo) do
        Igniter.Project.Config.configure(igniter, "config.exs", :my_app, :foo, nil,
          updater: fn _zipper -> :error end
        )
      else
        igniter
      end
      |> assert_unchanged()
    end

    test "it merges with 2 arg version of existing config" do
      test_project()
      |> Igniter.create_new_file("config/fake.exs", """
        import Config

        config :fake, buz: [:blat]
      """)
      |> apply_igniter!()
      |> Igniter.Project.Config.configure("fake.exs", :fake, [:foo, :bar], "baz")
      |> assert_has_patch("config/fake.exs", """
      3 - |config :fake, buz: [:blat]
      3 + |config :fake, buz: [:blat], foo: [bar: "baz"]
      """)
    end

    @tag :regression
    test "it handles this final `if` statement while formatting modules" do
      test_project()
      |> Igniter.create_new_file("config/test.exs", """
        import Config

        if __DIR__ |> Path.join("dev.secret.exs") |> File.exists?(), do: import_config("dev.secret.exs")

        import_config "host.exs"
      """)
      |> apply_igniter!()
      |> Igniter.Project.Module.create_module(Foo.Bar, "def foo, do: 10")
      |> Igniter.format(nil)
    end

    @tag :regression
    test "it sets the spark formatter plugins" do
      test_project()
      |> Igniter.Project.Config.configure(
        "fake.exs",
        :spark,
        [:formatter, :"Ash.Resource"],
        [],
        updater: fn x ->
          x
        end
      )
      |> Igniter.Project.Config.configure("fake.exs", :spark, [:formatter, :"Ash.Domain"], [],
        updater: fn x ->
          x
        end
      )
      |> assert_creates("config/fake.exs", """
      import Config
      config :spark, formatter: ["Ash.Resource": [], "Ash.Domain": []]
      """)
    end

    @tag :regression
    test "it merges the spark formatter plugins" do
      test_project()
      |> Igniter.create_new_file("config/fake.exs", """
      import Config
      config :spark, formatter: ["Ash.Resource": []]
      """)
      |> apply_igniter!()
      |> Igniter.Project.Config.configure(
        "fake.exs",
        :spark,
        [:formatter, :"Ash.Resource", :section_order],
        [:section],
        updater: fn zipper ->
          case Igniter.Code.List.prepend_new_to_list(zipper, :section) do
            {:ok, zipper} -> {:ok, zipper}
            :error -> {:ok, zipper}
          end
        end
      )
      |> assert_has_patch("config/fake.exs", """
      2 - |config :spark, formatter: ["Ash.Resource": []]
      2 + |config :spark, formatter: ["Ash.Resource": [section_order: [:section]]]
      """)
    end

    test "it merges with 2 arg version of existing config with a single path item" do
      test_project()
      |> Igniter.create_new_file("config/fake.exs", """
        import Config

        config :fake, buz: [:blat]
      """)
      |> apply_igniter!()
      |> Igniter.Project.Config.configure("fake.exs", :fake, [:foo], "baz")
      |> assert_has_patch(
        "config/fake.exs",
        """
        3   - |config :fake, buz: [:blat]
        3 + |config :fake, buz: [:blat], foo: "baz"
        """
      )
    end

    test "it chooses the 3 arg version when first item in path is not pretty" do
      test_project()
      |> Igniter.create_new_file("config/fake.exs", """
        import Config
      """)
      |> apply_igniter!()
      |> Igniter.Project.Config.configure("fake.exs", :fake, [Foo.Bar, :bar], "baz")
      |> assert_has_patch("config/fake.exs", """
      2 + |config :fake, Foo.Bar, bar: "baz"
      """)
    end

    test "it doesn't add non-pretty keys to existing config" do
      test_project()
      |> Igniter.create_new_file("config/fake.exs", """
        import Config
        config :fake, foo: 10
      """)
      |> apply_igniter!()
      |> Igniter.Project.Config.configure("fake.exs", :fake, [Foo.Bar, :bar], "baz")
      |> assert_has_patch("config/fake.exs", """
      2 + |config :fake, Foo.Bar, bar: "baz"
      """)
    end

    test "it chooses the 3 arg version when first item in path is not pretty, and merges that way" do
      test_project()
      |> Igniter.Project.Config.configure("fake.exs", :fake, [Foo.Bar, :bar], "baz")
      |> apply_igniter!()
      |> Igniter.Project.Config.configure("fake.exs", :fake, [Foo.Bar, :buz], "biz")
      |> assert_has_patch("config/fake.exs", """
      2   - |config :fake, Foo.Bar, bar: "baz"
      2 + |config :fake, Foo.Bar, bar: "baz", buz: "biz"
      """)
    end

    test "it merges with 3 arg version of existing config" do
      test_project()
      |> Igniter.create_new_file("config/fake.exs", """
        import Config

        config :fake, :buz, [:blat]
      """)
      |> apply_igniter!()
      |> Igniter.Project.Config.configure("fake.exs", :fake, [:foo, :bar], "baz")
      |> assert_has_patch("config/fake.exs", """
      3 + |config :fake, foo: [bar: "baz"]
      3 4 |config :fake, :buz, [:blat]
      """)
    end

    @tag :regression
    test "it merges with 3 arg version of existing config with the config set to []" do
      test_project()
      |> Igniter.create_new_file("config/fake.exs", """
        import Config

        config :foo, SomeModule, []
      """)
      |> apply_igniter!()
      |> Igniter.Project.Config.configure(
        "fake.exs",
        :foo,
        [SomeModule, :level1, :level2],
        :value
      )
      |> assert_has_patch("config/fake.exs", """
      3   - |config :foo, SomeModule, []
      3 + |config :foo, SomeModule, level1: [level2: :value]
      """)
    end

    @tag :regression
    test "it merges with 3 arg version of existing config with the config set to [] and the path is one level deeper than existing" do
      test_project()
      |> Igniter.create_new_file("config/fake.exs", """
        import Config

        config :foo, SomeModule, [level1: []]
      """)
      |> apply_igniter!()
      |> Igniter.Project.Config.configure(
        "fake.exs",
        :foo,
        [SomeModule, :level1, :level2, :level3],
        :value
      )
      |> assert_has_patch("config/fake.exs", """
      3 - |config :foo, SomeModule, level1: []
      3 + |config :foo, SomeModule, level1: [level2: [level3: :value]]
      """)
    end

    @tag :regression
    test "it merges with 2 arg version of existing config with the config set to [] and the path is one level deeper than existing" do
      test_project()
      |> Igniter.create_new_file(
        "config/fake.exs",
        """
          import Config

          config :level1,
            version: "1.0.0",
            level2: []
        """
      )
      |> apply_igniter!()
      |> Igniter.Project.Config.configure(
        "fake.exs",
        :level1,
        [:level2, :level3],
        1
      )
      |> assert_has_patch(
        "config/fake.exs",
        """
        3 3 |config :level1,
        4 4 |  version: "1.0.0",
        5 - |  level2: []
        5 + |  level2: [level3: 1]
        """
      )
    end

    test "it merges with 3 arg version of existing config with a single path item" do
      test_project()
      |> Igniter.create_new_file("config/fake.exs", """
        import Config

        config :fake, :buz, [:blat]
      """)
      |> apply_igniter!()
      |> Igniter.Project.Config.configure("fake.exs", :fake, [:foo], "baz")
      |> assert_has_patch("config/fake.exs", """
      3 + |config :fake, foo: "baz"
      3 4 |config :fake, :buz, [:blat]
      """)
    end

    test "present values can be updated" do
      test_project()
      |> Igniter.create_new_file("config/fake.exs", """
        import Config

        config :fake, :buz, [:blat]
      """)
      |> apply_igniter!()
      |> Igniter.Project.Config.configure("fake.exs", :fake, [:buz], "baz",
        updater: fn list ->
          Igniter.Code.List.prepend_new_to_list(list, "baz")
        end
      )
      |> assert_has_patch("config/fake.exs", """
      3 - |config :fake, :buz, [:blat]
      3 + |config :fake, :buz, ["baz", :blat]
      """)
    end

    test "we merge configs even in large config files" do
      test_project()
      |> Igniter.create_new_file("config/fake.exs", """
      # this is too

      import Config

      # this is a comment

      config :fake, :buz, [:blat]

      # trailing comment
      """)
      |> apply_igniter!()
      |> Igniter.Project.Config.configure("fake.exs", :fake, [:buz], "baz",
        updater: fn list ->
          Igniter.Code.List.prepend_new_to_list(list, "baz")
        end
      )
      |> assert_has_patch("config/fake.exs", """
      5  5   |# this is a comment
      6  6   |
      7    - |config :fake, :buz, [:blat]
         7 + |config :fake, :buz, ["baz", :blat]
      8  8   |
      9  9   |# trailing comment
      """)
    end

    test "integers can be used as values" do
      test_project()
      |> Igniter.create_new_file("config/fake.exs", """
        import Config

        config :fake, :buz, [:blat]
      """)
      |> apply_igniter!()
      |> Igniter.Project.Config.configure("fake.exs", :fake, [:buz], 12)
      |> assert_has_patch("config/fake.exs", """
      3 - |config :fake, :buz, [:blat]
      3 + |config :fake, :buz, 12
      """)
    end

    @tag :regression
    test "arbitrary data structures can be used as values" do
      test_project()
      |> Igniter.create_new_file("config/fake.exs", """
        import Config
        config :level1, :level2, level3: [{"hello", "world"}]
      """)
      |> apply_igniter!()
      |> Igniter.Project.Config.configure(
        "fake.exs",
        :level1,
        [:level2, :level3],
        [
          {"hello1", "world1"}
        ]
      )
      |> assert_has_patch("config/fake.exs", """
      2   - |config :level1, :level2, level3: [{"hello", "world"}]
        2 + |config :level1, :level2, level3: [{"hello1", "world1"}]
      """)
    end

    @tag :regression
    test "quoted code can be used as values" do
      test_project()
      |> Igniter.create_new_file(
        "config/fake.exs",
        """
          import Config

          config :tailwind,
            version: "1.0.0",
            default: []
        """
      )
      |> Igniter.Project.Config.configure(
        "fake.exs",
        :tailwind,
        [:default, :args],
        {:code,
         Sourceror.parse_string!("""
         ~w(--config=tailwind.config.js --input=css/app.css --output=../output/assets/app.css)
         """)}
      )
      |> Igniter.Project.Config.configure(
        "fake.exs",
        :tailwind,
        [:default, :cd],
        {:code,
         Sourceror.parse_string!("""
         Path.expand("../assets", __DIR__)
         """)}
      )
      |> assert_creates("config/fake.exs", """
      import Config

      config :tailwind,
        version: "1.0.0",
        default: [
          args: ~w(--config=tailwind.config.js --input=css/app.css --output=../output/assets/app.css),
          cd: Path.expand("../assets", __DIR__)
        ]
      """)
    end

    test "present values can be updated by updating map keys" do
      test_project()
      |> Igniter.create_new_file("config/fake.exs", """
        import Config

        config :fake, foo: %{"a" => ["a", "b"]}
      """)
      |> apply_igniter!()
      |> Igniter.Project.Config.configure("fake.exs", :fake, [:foo], %{"b" => ["c", "d"]},
        updater: fn zipper ->
          Igniter.Code.Map.set_map_key(zipper, "b", ["c", "d"], fn zipper ->
            with {:ok, zipper} <- Igniter.Code.List.prepend_new_to_list(zipper, "c") do
              Igniter.Code.List.prepend_new_to_list(zipper, "d")
            end
          end)
        end
      )
      |> assert_has_patch("config/fake.exs", """
      3   - |config :fake, foo: %{"a" => ["a", "b"]}
        3 + |config :fake, foo: %{"a" => ["a", "b"], "b" => ["c", "d"]}
      """)
    end

    test "it presents users with instructions on how to update a malformed config" do
      assert {:ok, _igniter,
              %{
                warnings: [
                  """
                  Please set the following config in config/fake.exs:

                      config :fake, foo: %{"b" => ["c", "d"]}

                  A failure message!
                  """
                ]
              }} =
               test_project()
               |> Igniter.create_new_file("config/fake.exs", """
                 config :fake, foo: %{"a" => ["a", "b"]}
               """)
               |> apply_igniter!()
               |> Igniter.Project.Config.configure(
                 "fake.exs",
                 :fake,
                 [:foo],
                 %{"b" => ["c", "d"]},
                 failure_message: "A failure message!"
               )
               |> apply_igniter()
    end

    test "places code after last matching node" do
      test_project()
      |> Igniter.create_new_file("config/fake.exs", """
      import Config

      foo = 1
      foo = 2

      if System.get_env("PHX_SERVER") do
        config :fake, FakeWeb.Endpoint, server: true
      end
      """)
      |> apply_igniter!()
      |> Igniter.Project.Config.configure(
        "fake.exs",
        :fake,
        [:foo],
        {:code, Sourceror.parse_string!("foo")},
        after: &match?({:=, _, [{:foo, _, _}, _]}, &1.node)
      )
      |> assert_has_patch("config/fake.exs", """
      4  4   |foo = 2
      5  5   |
         6 + |config :fake, foo: foo
         7 + |
      6  8   |if System.get_env("PHX_SERVER") do
      """)
    end

    test "places code into next config after matching node" do
      test_project()
      |> Igniter.create_new_file("config/fake.exs", """
      import Config

      foo = "bar"
      bar = "baz"

      config :fake, bar: [:baz]

      if System.get_env("PHX_SERVER") do
        config :fake, FakeWeb.Endpoint, server: true
      end
      """)
      |> apply_igniter!()
      |> Igniter.Project.Config.configure(
        "fake.exs",
        :fake,
        [:foo],
        {:code, Sourceror.parse_string!("foo")},
        after: &match?({:=, _, [{:foo, _, _}, _]}, &1.node)
      )
      |> assert_has_patch("config/fake.exs", """
      4  4   |bar = "baz"
      5  5   |
      6    - |config :fake, bar: [:baz]
         6 + |config :fake, bar: [:baz], foo: foo
      """)
    end

    test "respect mix.exs :config_path" do
      mix_exs = """
      defmodule Test.MixProject do
        use Mix.Project

        def project do
          [
            app: :test,
            config_path: "../../config/config.exs"
          ]
        end
      end
      """

      igniter =
        assert test_project()
               |> Igniter.create_or_update_elixir_file(
                 "mix.exs",
                 mix_exs,
                 &{:ok, Igniter.Code.Common.replace_code(&1, mix_exs)}
               )
               |> apply_igniter!()

      igniter
      |> Igniter.Project.Config.configure("fake.exs", :fake, [:foo, :bar], "baz")
      |> assert_creates("../../config/fake.exs", """
      import Config
      config :fake, foo: [bar: "baz"]
      """)
    end
  end

  @tag :regression
  test "works with conditional import present in config file" do
    # this test just asserts no error is raised doing this
    test_project()
    |> Igniter.create_new_file("config/config.exs", """
    import Config
    config :foo, :bar, 10

    if Mix.target() == :host do
      import_config "host.exs"
    else
      import_config "target.exs"
    end
    """)
    |> apply_igniter!()
  end

  test "configures_root_key?/3" do
    igniter =
      test_project()
      |> Igniter.create_new_file("config/fake.exs", """
      import Config

      config :foo, key1: "key1"
      config Test, key2: "key2"
      """)
      |> apply_igniter!()

    assert Igniter.Project.Config.configures_root_key?(igniter, "fake.exs", :foo) == true
    assert Igniter.Project.Config.configures_root_key?(igniter, "fake.exs", :fooo) == false
    assert Igniter.Project.Config.configures_root_key?(igniter, "fake.exs", Test) == true
    assert Igniter.Project.Config.configures_root_key?(igniter, "fake.exs", Testt) == false
  end

  describe "configure_runtime_env/6" do
    test "present value is overwritten by default" do
      test_project()
      |> Igniter.create_new_file("config/runtime.exs", """
      import Config

      if config_env() == :prod do
        config :fake, :buz, :blat
      end
      """)
      |> apply_igniter!()
      |> Igniter.Project.Config.configure_runtime_env(:prod, :fake, [:buz], "baz")
      |> assert_has_patch("config/runtime.exs", """
      4 - |  config :fake, :buz, :blat
      4 + |  config :fake, :buz, "baz"
      """)
    end
  end

  describe "configures_key?/3" do
    setup do
      %{
        igniter:
          test_project()
          |> Igniter.create_new_file("config/fake.exs", """
          import Config

          config :foo, key1: [key2: "key2"]
          config :bar, Test, key3: "key3"
          config :xyz, Test, key4: [key5: "key5"]
          """)
          |> apply_igniter!()
      }
    end

    test "works when the last argument is a single atom and config/2 is used", %{igniter: igniter} do
      assert Igniter.Project.Config.configures_key?(igniter, "fake.exs", :foo, :key1) == true
      assert Igniter.Project.Config.configures_key?(igniter, "fake.exs", :foo, :key2) == false
    end

    test "works when the last argument is a single atom and config/3 is used", %{igniter: igniter} do
      assert Igniter.Project.Config.configures_key?(igniter, "fake.exs", :bar, Test) == true
      assert Igniter.Project.Config.configures_key?(igniter, "fake.exs", :bar, Testt) == false
    end

    test "works when the last argument is a path in a keyword list and config/2 is used", %{
      igniter: igniter
    } do
      assert Igniter.Project.Config.configures_key?(igniter, "fake.exs", :foo, [:key1, :key2]) ==
               true

      assert Igniter.Project.Config.configures_key?(igniter, "fake.exs", :foo, [:key1, :key3]) ==
               false
    end

    test "works when the last argument is a path in a keyword list and config/3 is used", %{
      igniter: igniter
    } do
      assert Igniter.Project.Config.configures_key?(igniter, "fake.exs", :bar, [Test, :key3]) ==
               true

      assert Igniter.Project.Config.configures_key?(igniter, "fake.exs", :bar, [Test, :key4]) ==
               false

      # deeply nested
      assert Igniter.Project.Config.configures_key?(igniter, "fake.exs", :xyz, [
               Test,
               :key4,
               :key5
             ]) ==
               true

      assert Igniter.Project.Config.configures_key?(igniter, "fake.exs", :xyz, [
               Test,
               :key4,
               :key6
             ]) ==
               false
    end
  end

  describe "modify_configuration_code/5" do
    test "replace existing config" do
      zipper =
        ~s"""
        import Config
        config :fake, foo: [bar: "baz"]
        """
        |> Sourceror.parse_string!()
        |> Sourceror.Zipper.zip()

      config =
        zipper
        |> Igniter.Project.Config.modify_config_code([:foo], :fake, true)
        |> elem(1)
        |> Igniter.Util.Debug.code_at_node()

      assert String.contains?(config, "config :fake, foo: true")
    end

    test "update existing config" do
      zipper =
        ~s"""
        import Config
        config :fake, foo: [bar: "baz"]
        """
        |> Sourceror.parse_string!()
        |> Sourceror.Zipper.zip()

      config =
        zipper
        |> Igniter.Project.Config.modify_config_code([:foo], :fake, true,
          updater: fn zipper ->
            Igniter.Code.Keyword.put_in_keyword(zipper, [:bar], true)
          end
        )
        |> elem(1)
        |> Igniter.Util.Debug.code_at_node()

      assert String.contains?(config, "config :fake, foo: [bar: true]")
    end

    test "update existing config twice" do
      zipper =
        ~s"""
        import Config
        """
        |> Sourceror.parse_string!()
        |> Sourceror.Zipper.zip()

      config =
        zipper
        |> Igniter.Project.Config.modify_config_code([:a], :app, 1)
        |> elem(1)
        |> Igniter.Project.Config.modify_config_code([:b], :app, 2)
        |> elem(1)
        |> Igniter.Util.Debug.code_at_node()

      assert String.contains?(config, "config :app, a: 1, b: 2")
    end
  end

  describe "configure_group" do
    test "adds configuration with a comment above it" do
      test_project()
      |> Igniter.Project.Config.configure_group(
        "config.exs",
        :foo,
        [:bar],
        [
          {:baz, :buz}
        ],
        comment: """
          Configures the foobar to
          accomplish the barbaz
        """
      )
      |> assert_creates("config/config.exs", """
      #  Configures the foobar to
      #  accomplish the barbaz
      import Config
      config :foo, bar: [baz: :buz]
      """)
    end

    test "alters configuration without adding a comment if the group is already configured" do
      test_project()
      |> Igniter.Project.Config.configure("config.exs", :foo, [:bar], [])
      |> apply_igniter!()
      |> Igniter.Project.Config.configure_group(
        "config.exs",
        :foo,
        [:bar],
        [
          {:baz, :buz}
        ],
        comment: """
          Configures the foobar to
          accomplish the barbaz
        """
      )
      |> assert_has_patch("config/config.exs", """
       - |config :foo, bar: []
       + |config :foo, bar: [baz: :buz]
      """)
    end
  end

  describe "remove_application_configuration/3" do
    test "it does not create the config file if it does not exist" do
      test_project()
      |> Igniter.Project.Config.remove_application_configuration("fake.exs", :fake)
      |> refute_creates("config/fake.exs")
    end

    test "it removes the applications configuration if it exists" do
      test_project()
      |> Igniter.create_new_file("config/fake.exs", """
        import Config

        config :fake, buz: [:blat]
      """)
      |> apply_igniter!()
      |> Igniter.Project.Config.remove_application_configuration("fake.exs", :fake)
      |> assert_has_patch("config/fake.exs", """
      3 - |config :fake, buz: [:blat]
      """)
    end

    test "it removes duplicate application configurations" do
      test_project()
      |> Igniter.create_new_file("config/fake.exs", """
        import Config

        config :fake, buz: [:blat]
        config :fake, bar: [:blot]
      """)
      |> apply_igniter!()
      |> Igniter.Project.Config.remove_application_configuration("fake.exs", :fake)
      |> assert_has_patch("config/fake.exs", """
      3 - |config :fake, buz: [:blat]
      4 - |config :fake, bar: [:blot]
      """)
    end
  end
end
