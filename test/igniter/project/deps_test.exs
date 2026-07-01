# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Igniter.Project.DepsTest do
  use ExUnit.Case, async: false
  use Mimic

  import Igniter.Test

  setup_all do
    Mimic.copy(Req)
    Mimic.copy(Igniter.Util.IO)
    Mimic.copy(Igniter.Mix.Task)
    :ok
  end

  describe "add_dep/3" do
    test "adds the provided dependency" do
      assert {:ok, nil} = Igniter.Project.Deps.get_dep(Igniter.new(), :foobar)

      igniter = Igniter.Project.Deps.add_dep(Igniter.new(), {:foobar, "~> 2.0"})

      assert Igniter.Project.Deps.get_dep(igniter, :foobar) ==
               {:ok, "{:foobar, \"~> 2.0\"}"}
    end

    test "adds the provided dependency in a tuple format" do
      test_project()
      |> Igniter.Project.Deps.add_dep({:foobar, "~> 2.0"})
      |> assert_has_patch("mix.exs", "+ | {:foobar, \"~> 2.0\"}")
      |> Igniter.Project.Deps.add_dep({:barfoo, "~> 1.0"})
      |> assert_has_patch("mix.exs", "+ | {:barfoo, \"~> 1.0\"}")
    end

    test "adds the provided dependency with options" do
      assert {:ok, nil} = Igniter.Project.Deps.get_dep(Igniter.new(), :foobar)

      igniter = Igniter.Project.Deps.add_dep(Igniter.new(), {:foobar, "~> 2.0", only: :test})

      assert {:ok, "{:foobar, \"~> 2.0\", only: :test}"} =
               Igniter.Project.Deps.get_dep(igniter, :foobar)
    end

    test "can be configured to add deps to a specific variable" do
      igniter =
        test_project(
          files: %{
            "mix.exs" => """
            defmodule Test.MixProject do
              use Mix.Project

              def project do
                [
                  app: :test,
                  version: "0.1.0",
                  elixir: "~> 1.17",
                  start_permanent: Mix.env() == :prod,
                  deps: deps()
                ]
              end

              # Run "mix help compile.app" to learn about applications.
              def application do
                [
                  extra_applications: [:logger]
                ]
              end

              # Run "mix help deps" to learn about dependencies.
              defp deps do
                deps = []

                if 1 == 2 do
                  deps
                else
                  deps ++ [{:req, "~> 1.0"}]
                end
              end
            end
            """
          }
        )
        |> Igniter.Project.IgniterConfig.configure(
          :deps_location,
          {:variable, :deps}
        )

      igniter =
        igniter
        |> Igniter.Project.Deps.add_dep({:foobar, "~> 2.0"})
        |> assert_has_patch("mix.exs", """
        + |    deps = [{:foobar, "~> 2.0"}]
        """)

      refute :foobar in (igniter.assigns[:failed_to_add_deps] || [])
    end

    test "tracks when deps fail to be added" do
      igniter =
        test_project(
          files: %{
            "mix.exs" => """
            defmodule Test.MixProject do
              use Mix.Project

              def project do
                [
                  app: :test,
                  version: "0.1.0",
                  elixir: "~> 1.17",
                  start_permanent: Mix.env() == :prod,
                  deps: deps()
                ]
              end

              # Run "mix help compile.app" to learn about applications.
              def application do
                [
                  extra_applications: [:logger]
                ]
              end

              # Run "mix help deps" to learn about dependencies.
              defp deps do
                deps = []

                if 1 == 2 do
                  deps
                else
                  deps ++ [{:req, "~> 1.0"}]
                end
              end
            end
            """
          }
        )

      igniter =
        Igniter.Project.Deps.add_dep(igniter, {:foobar, "~> 2.0", only: :test})

      assert :foobar in igniter.assigns[:failed_to_add_deps]
    end
  end

  describe "add_dep/3 replace prompt (#338)" do
    setup :verify_on_exit!

    test "shows readable quoted runtime in Desired/Found when replacing an existing dep" do
      igniter =
        test_project(
          files: %{
            "mix.exs" => """
            defmodule Test.MixProject do
              use Mix.Project

              def project do
                [
                  app: :test,
                  version: "0.1.0",
                  elixir: "~> 1.17",
                  start_permanent: Mix.env() == :prod,
                  deps: deps()
                ]
              end

              def application do
                [extra_applications: [:logger]]
              end

              defp deps do
                [
                  {:esbuild, "~> 0.8", runtime: true}
                ]
              end
            end
            """
          }
        )

      expect(Igniter.Util.IO, :yes?, fn prompt ->
        assert prompt =~ "Desired:"
        assert prompt =~ "Found:"

        # https://github.com/ash-project/igniter/issues/338
        assert prompt =~ "Mix.env() == :dev"
        refute prompt =~ ":__aliases__"
        refute prompt =~ "context:"

        false
      end)

      Igniter.Project.Deps.add_dep(
        igniter,
        {:esbuild, "~> 0.10", runtime: quote(do: Mix.env() == :dev)}
      )
    end
  end

  describe "set_dep_option" do
    test "sets the option when no options exist" do
      test_project()
      |> Igniter.Project.Deps.add_dep({:foobar, "~> 2.0"})
      |> apply_igniter!()
      |> Igniter.Project.Deps.set_dep_option(:foobar, :only, :test)
      |> assert_has_patch("mix.exs", """
      - | {:foobar, "~> 2.0"}
      + | {:foobar, "~> 2.0", only: :test}
      """)
    end
  end

  describe "get_dep/2" do
    test "detects existing dependencies when using deps_location variable" do
      igniter =
        test_project(
          files: %{
            "mix.exs" => """
            defmodule Test.MixProject do
              use Mix.Project

              def project do
                [
                  app: :test,
                  version: "0.1.0",
                  elixir: "~> 1.17",
                  start_permanent: Mix.env() == :prod,
                  deps: deps()
                ]
              end

              # Run "mix help compile.app" to learn about applications.
              def application do
                [
                  extra_applications: [:logger]
                ]
              end

              # Run "mix help deps" to learn about dependencies.
              defp deps do
                shared_deps = [
                  {:ash_authentication, "~> 4.0"},
                  {:picosat_elixir, "~> 0.2"},
                  {:ash, "~> 3.5"}
                ]

                shared_deps
              end
            end
            """
          }
        )
        |> Igniter.Project.IgniterConfig.configure(
          :deps_location,
          {:variable, :shared_deps}
        )

      # Should detect existing dependency
      assert {:ok, "{:ash_authentication, \"~> 4.0\"}"} =
               Igniter.Project.Deps.get_dep(igniter, :ash_authentication)

      assert {:ok, "{:ash, \"~> 3.5\"}"} =
               Igniter.Project.Deps.get_dep(igniter, :ash)

      # Should return nil for non-existing dependency
      assert {:ok, nil} =
               Igniter.Project.Deps.get_dep(igniter, :non_existing_dep)
    end

    test "prevents duplicate dependencies when using deps_location variable" do
      igniter =
        test_project(
          files: %{
            "mix.exs" => """
            defmodule Test.MixProject do
              use Mix.Project

              def project do
                [
                  app: :test,
                  version: "0.1.0",
                  elixir: "~> 1.17",
                  start_permanent: Mix.env() == :prod,
                  deps: deps()
                ]
              end

              # Run "mix help compile.app" to learn about applications.
              def application do
                [
                  extra_applications: [:logger]
                ]
              end

              # Run "mix help deps" to learn about dependencies.
              defp deps do
                shared_deps = [
                  {:ash_authentication, "~> 4.0"},
                  {:picosat_elixir, "~> 0.2"},
                  {:ash, "~> 3.5"}
                ]

                shared_deps
              end
            end
            """
          }
        )
        |> Igniter.Project.IgniterConfig.configure(
          :deps_location,
          {:variable, :shared_deps}
        )

      # Try to add an existing dependency - should not create duplicate
      igniter = Igniter.Project.Deps.add_dep(igniter, {:ash_authentication, "~> 4.0"})

      # Should still detect the existing dependency correctly
      assert {:ok, "{:ash_authentication, \"~> 4.0\"}"} =
               Igniter.Project.Deps.get_dep(igniter, :ash_authentication)

      # Should not have failed to add the dependency (no duplicates created)
      refute :ash_authentication in (igniter.assigns[:failed_to_add_deps] || [])
    end
  end

  describe "determine_dep_type_and_version/1" do
    test "parses to a version" do
      tests = [
        "dep@1.0.0": {:dep, "== 1.0.0"},
        "dep@1.0": {:dep, "~> 1.0"},
        "dep@git:git_url": {:dep, git: "git_url", override: true},
        "dep@git:git_url@ref": {:dep, git: "git_url", ref: "ref", override: true},
        "dep@github:user/repo": {:dep, github: "user/repo", override: true},
        "dep@github:user/repo@ref": {:dep, github: "user/repo", ref: "ref", override: true},
        "dep@path:path/to/dep": {:dep, path: "path/to/dep", override: true},
        "org/dep@1.0.0": {:dep, "== 1.0.0", organization: "org"},
        "org/dep@1.0": {:dep, "~> 1.0", organization: "org"},
        "org/dep@git:git_url": {:dep, git: "git_url", override: true, organization: "org"},
        "org/dep@git:git_url@ref":
          {:dep, git: "git_url", ref: "ref", override: true, organization: "org"},
        "org/dep@github:user/repo":
          {:dep, github: "user/repo", override: true, organization: "org"},
        "org/dep@github:user/repo@ref":
          {:dep, github: "user/repo", ref: "ref", override: true, organization: "org"},
        "org/dep@github:user/repo@branch@name":
          {:dep, github: "user/repo", ref: "branch@name", override: true, organization: "org"},
        "org/dep@github:user/repo@branch/name":
          {:dep, github: "user/repo", ref: "branch/name", override: true, organization: "org"},
        "org/dep@path:path/to/dep":
          {:dep, path: "path/to/dep", override: true, organization: "org"}
      ]

      for {spec, expected} <- tests do
        assert spec |> to_string() |> Igniter.Project.Deps.determine_dep_type_and_version!() ==
                 expected
      end
    end
  end

  describe "hex install confirmation popup" do
    @package "testpkg"
    @package_url "https://hex.pm/api/packages/testpkg"

    setup :verify_on_exit!

    setup do
      stub(Igniter.Mix.Task, :tty?, fn -> true end)
      stub(Igniter.Util.IO, :yes?, fn _prompt -> true end)
      :ok
    end

    defp collect_mix_shell_info(acc) do
      receive do
        {:mix_shell, :info, [payload]} -> collect_mix_shell_info([payload | acc])
      after
        0 -> Enum.reverse(acc)
      end
    end

    defp capture_confirmation_banner(fun) do
      Mix.shell(Mix.Shell.Process)

      try do
        fun.()
        payloads = collect_mix_shell_info([])

        payloads
        |> Enum.map(fn p -> Enum.map_join(List.wrap(p), "", &IO.ANSI.format/1) end)
        |> Enum.reject(&(&1 == ""))
        |> Enum.join("")
      after
        Mix.shell(Mix.Shell.IO)
      end
    end

    defp release_url(version) do
      @package_url <> "/releases/" <> URI.encode(version, &URI.char_unreserved?/1)
    end

    defp stub_hex_api(package_body, release_body) do
      version = release_body["version"]
      release_api_url = release_url(version)

      stub(Req, :get, fn url, _opts ->
        cond do
          url == release_api_url ->
            {:ok, %{status: 200, body: release_body}}

          url == @package_url ->
            {:ok, %{status: 200, body: package_body}}

          true ->
            flunk("unexpected Req.get URL: #{url}")
        end
      end)
    end

    defp run_hex_install(package_body, release_body, opts \\ []) do
      argv = Keyword.get(opts, :argv, [])
      stub_hex_api(package_body, release_body)

      capture_confirmation_banner(fn ->
        Igniter.Project.Deps.determine_dep_type_and_version!(@package, argv: argv)
      end)
    end

    defp base_package_body(overrides \\ %{}) do
      Map.merge(
        %{
          "releases" => [
            %{
              "version" => "1.2.3",
              "inserted_at" => "2024-05-15T12:00:00Z"
            }
          ],
          "meta" => %{"description" => "A great package"},
          "owners" => [
            %{"username" => "alice"},
            %{"username" => "bob"}
          ],
          "downloads" => %{"week" => 1234, "all" => 1_234_567}
        },
        overrides
      )
    end

    defp base_release_body(overrides \\ %{}) do
      Map.merge(
        %{
          "version" => "1.2.3",
          "inserted_at" => "2024-05-15T12:00:00Z",
          "requirements" => %{"plug" => "~> 1.0", "jason" => "~> 1.0"},
          "publisher" => %{"username" => "publisher1"},
          "downloads" => 9876
        },
        overrides
      )
    end

    defp expected_banner(fields) do
      """

      You are installing the package "#{fields.package}":

      Description:       #{fields.description}
      Current version:   #{fields.version} (released #{fields.release_date})
      hex.pm authors:    #{fields.authors}
      hex.pm publishers: #{fields.publishers}
      Dependencies:      #{fields.deps}
      Downloads:         #{fields.downloads_this_version} (this version), #{fields.downloads_week} (last 7 days), #{fields.downloads_all} (all time)

      """
    end

    test "shows full confirmation banner with complete metadata" do
      output =
        run_hex_install(
          base_package_body(),
          base_release_body()
        )

      assert output ==
               expected_banner(%{
                 package: @package,
                 description: "A great package",
                 version: "1.2.3",
                 release_date: "2024-05-15",
                 authors: "alice, bob",
                 publishers: "publisher1",
                 deps: "jason, plug",
                 downloads_this_version: "9 876",
                 downloads_week: "1 234",
                 downloads_all: "1 234 567"
               })
    end

    test "shows N/A when meta description is missing" do
      package_body = base_package_body(%{"meta" => %{}})

      output =
        run_hex_install(
          package_body,
          base_release_body()
        )

      assert output =~ "Description:       N/A"
    end

    test "shows Dependencies N/A when requirements map is empty" do
      output =
        run_hex_install(
          base_package_body(),
          base_release_body(%{"requirements" => %{}})
        )

      assert output =~ "Dependencies:      N/A"
    end

    test "shows N/A in Downloads line when download fields are missing" do
      package_body = base_package_body(%{"downloads" => %{}})

      output =
        run_hex_install(
          package_body,
          base_release_body(%{"downloads" => nil})
        )

      assert output =~
               "Downloads:         N/A (this version), N/A (last 7 days), N/A (all time)"
    end

    test "formats integer downloads with thousands separators and negative prefix" do
      package_body = base_package_body(%{"downloads" => %{"week" => -5432, "all" => 1_000_000}})

      output =
        run_hex_install(
          package_body,
          base_release_body(%{"downloads" => -12_345})
        )

      assert output =~
               "Downloads:         -12 345 (this version), -5 432 (last 7 days), 1 000 000 (all time)"
    end

    test "falls back to owners for publishers when release has no publisher" do
      output =
        run_hex_install(
          base_package_body(),
          base_release_body(%{"publisher" => nil})
        )

      assert output =~ "hex.pm publishers: alice, bob"
    end

    test "shows N/A for authors and publishers when owners list is empty" do
      output =
        run_hex_install(
          base_package_body(%{"owners" => []}),
          base_release_body(%{"publisher" => nil})
        )

      assert output =~ "hex.pm authors:    N/A"
      assert output =~ "hex.pm publishers: N/A"
    end

    test "collapses embedded newlines in description to spaces" do
      package_body =
        base_package_body(%{
          "meta" => %{"description" => "Line one\nLine two"}
        })

      output =
        run_hex_install(
          package_body,
          base_release_body()
        )

      assert output =~ "Description:       Line one Line two"
    end

    test "shows N/A for release date when inserted_at is empty" do
      release_body = base_release_body(%{"inserted_at" => ""})

      package_body =
        base_package_body(%{
          "releases" => [
            %{"version" => "1.2.3", "inserted_at" => ""}
          ]
        })

      output =
        run_hex_install(
          package_body,
          release_body
        )

      assert output =~ "Current version:   1.2.3 (released N/A)"
    end

    test "skips confirmation banner when argv contains --yes" do
      stub_hex_api(base_package_body(), base_release_body())

      output =
        capture_confirmation_banner(fn ->
          result =
            Igniter.Project.Deps.determine_dep_type_and_version!(@package, argv: ["--yes"])

          assert result == {:testpkg, "~> 1.0"}
        end)

      assert output == ""
    end

    test "handles atom keys in release entry after hex_string_key_map merge" do
      package_body =
        base_package_body(%{
          "releases" => [
            %{
              "version" => "2.0.0",
              :inserted_at => "2024-06-01T00:00:00Z"
            }
          ]
        })

      release_body =
        base_release_body(%{
          "version" => "2.0.0",
          "inserted_at" => "2024-06-01T00:00:00Z"
        })

      output =
        run_hex_install(
          package_body,
          release_body
        )

      assert output =~ "Current version:   2.0.0 (released 2024-06-01)"
    end
  end
end
