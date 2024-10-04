defmodule Igniter.Libs.EctoTest do
  use ExUnit.Case, async: false
  import Igniter.Test

  setup do
    current_shell = Mix.shell()

    :ok = Mix.shell(Mix.Shell.Process)

    on_exit(fn ->
      Mix.shell(current_shell)
    end)
  end

  describe "list_repos" do
    test "returns the list of repos" do
      {_igniter, repos} =
        test_project()
        |> Igniter.Project.Module.create_module(Example.Repo, "use Ecto.Repo")
        |> Igniter.Project.Module.create_module(Example.Repo2, "use AshPostgres.Repo")
        |> Igniter.Libs.Ecto.list_repos()

      assert Enum.sort(repos) == [Example.Repo, Example.Repo2]
    end
  end

  describe "select_repo" do
    test "returns the selected repo" do
      send(self(), {:mix_shell_input, :prompt, "0"})

      assert {_igniter, Example.Repo} =
               test_project()
               |> Igniter.Project.Module.create_module(Example.Repo, "use Ecto.Repo")
               |> Igniter.Project.Module.create_module(Example.Repo2, "use AshPostgres.Repo")
               |> Igniter.Libs.Ecto.select_repo(label: "Which repo would you like to use?")
    end
  end

  describe "gen_migration" do
    test "it generates a migration file" do
      test_project()
      |> Igniter.Libs.Ecto.gen_migration(Example.Repo, "create_users",
        body: """
        def up do
          "up"
        end

        def down do
          "down"
        end
        """,
        timestamp: 00
      )
      |> assert_creates("priv/repo/migrations/0_create_users.exs", """
      defmodule Example.Repo.Migrations.CreateUsers do
        use Ecto.Migration

        def up do
          "up"
        end

        def down do
          "down"
        end
      end
      """)
    end
  end
end
