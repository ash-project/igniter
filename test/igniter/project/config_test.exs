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
        |> Igniter.Project.Config.modify_configuration_code([:foo], :fake, true)
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
        |> Igniter.Project.Config.modify_configuration_code([:foo], :fake, true, fn zipper ->
            Igniter.Code.Keyword.put_in_keyword(zipper, [:bar], true) 
        end)
        |> Igniter.Util.Debug.code_at_node()

      assert String.contains?(config, "config :fake, foo: [bar: true]")
    end

  end

end
