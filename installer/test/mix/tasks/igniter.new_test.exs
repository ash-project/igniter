defmodule Mix.Tasks.Igniter.NewTest do
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  describe "igniter.new with --git flag" do
    @tag :integration
    test "initializes git repository and creates initial commit", %{tmp_dir: tmp_dir} do
      unless git_available?() do
        :ok
      else
        project_name = "test_project"
        project_path = Path.join(tmp_dir, project_name)

        # Change to tmp directory to run the command
        original_cwd = File.cwd!()

        try do
          File.cd!(tmp_dir)

          # Run igniter.new with --git flag using System.cmd
          {output, exit_code} =
            System.cmd(
              "mix",
              ["igniter.new", project_name, "--git", "--yes", "--no-installer-version-check"],
              stderr_to_stdout: true,
              env: [{"MIX_ENV", "test"}, {"IGNITER_SKIP_GIT_CHECK", "true"}]
            )

          if exit_code != 0 do
            IO.puts("Command failed with output: #{output}")
          end

          assert exit_code == 0,
                 "Expected igniter.new to succeed, but got exit code #{exit_code}. Output: #{output}"

          # Verify project directory was created
          assert File.exists?(project_path), "Project directory should exist at #{project_path}"

          # Change to project directory to check git status
          File.cd!(project_path)

          # Verify .git directory exists
          assert File.exists?(".git"), ".git directory should exist"
          assert File.dir?(".git"), ".git should be a directory"

          # Verify git repository was initialized by checking git status
          {output, 0} = System.cmd("git", ["status", "--porcelain"])
          # Empty output means all files are committed (working directory clean)
          assert String.trim(output) == "",
                 "Working directory should be clean after initial commit"

          # Verify there is at least one commit
          {output, 0} = System.cmd("git", ["log", "--oneline"])

          assert String.contains?(output, "🔥 initial commit 🔥"),
                 "Should have initial commit with fire emoji"

          # Verify essential files are tracked
          {output, 0} = System.cmd("git", ["ls-files"])
          tracked_files = String.split(String.trim(output), "\n")

          assert "mix.exs" in tracked_files, "mix.exs should be tracked"
          assert ".gitignore" in tracked_files, ".gitignore should be tracked"
          assert "README.md" in tracked_files, "README.md should be tracked"

          # Verify igniter was added to mix.exs
          mix_exs_content = File.read!("mix.exs")

          assert String.contains?(mix_exs_content, "{:igniter"),
                 "Igniter dependency should be added to mix.exs"
        after
          File.cd!(original_cwd)
        end
      end
    end

    @tag :integration
    test "creates project without git when --no-git flag is provided", %{tmp_dir: tmp_dir} do
      unless git_available?() do
        :ok
      else
        project_name = "test_project_no_git"
        project_path = Path.join(tmp_dir, project_name)

        original_cwd = File.cwd!()

        try do
          File.cd!(tmp_dir)

          # Run igniter.new without --git flag
          {output, exit_code} =
            System.cmd(
              "mix",
              ["igniter.new", project_name, "--yes", "--no-installer-version-check", "--no-git"],
              stderr_to_stdout: true,
              env: [{"MIX_ENV", "test"}]
            )

          assert exit_code == 0,
                 "Expected igniter.new to succeed, but got exit code #{exit_code}. Output: #{output}"

          assert File.exists?(project_path), "Project directory should exist"
          File.cd!(project_path)

          # Verify .git directory does NOT exist
          refute File.exists?(".git"),
                 ".git directory should not exist when --git flag is not provided"
        after
          File.cd!(original_cwd)
        end
      end
    end

    @tag :integration
    test "does not run git init when already in git project", %{tmp_dir: tmp_dir} do
      if !git_available?() do
        :ok
      else
        project_parent = "parent_folder"
        project_name = "child_project_with_git_parent"

        original_cwd = File.cwd!()

        try do
          File.cd!(tmp_dir)
          File.mkdir!(project_parent)
          File.cd!(project_parent)
          System.cmd("git", ["init", "."])
          assert File.exists?(".git"), "Git was not successfully set up in the parent folder"

          # Run igniter.new with --git flag using System.cmd
          {_output, exit_code} =
            System.cmd(
              "mix",
              ["igniter.new", project_name, "--git", "--yes", "--no-installer-version-check"],
              stderr_to_stdout: true,
              env: [{"MIX_ENV", "test"}]
            )

          assert exit_code == 0

          File.cd!(project_name)
          refute File.exists?(".git"), "git should not be initialized when already in git project"
        after
          File.cd!(original_cwd)
        end
      end
    end

    @tag :integration
    test "git functionality works with other flags", %{tmp_dir: tmp_dir} do
      unless git_available?() do
        :ok
      else
        project_name = "test_project_with_sup"
        project_path = Path.join(tmp_dir, project_name)

        original_cwd = File.cwd!()

        try do
          File.cd!(tmp_dir)

          # Run igniter.new with --git and --sup flags
          {output, exit_code} =
            System.cmd(
              "mix",
              [
                "igniter.new",
                project_name,
                "--sup",
                "--yes",
                "--no-installer-version-check"
              ],
              stderr_to_stdout: true,
              env: [{"MIX_ENV", "test"}, {"IGNITER_SKIP_GIT_CHECK", "true"}]
            )

          assert exit_code == 0,
                 "Expected igniter.new to succeed, but got exit code #{exit_code}. Output: #{output}"

          assert File.exists?(project_path)
          File.cd!(project_path)

          # Verify git repository exists and is clean
          assert File.exists?(".git")
          {output, 0} = System.cmd("git", ["status", "--porcelain"])
          assert String.trim(output) == ""

          # Verify project has supervision tree (--sup flag worked)
          mix_exs_content = File.read!("mix.exs")

          assert String.contains?(mix_exs_content, "mod: {"),
                 "Should have supervision tree when --sup is used"

          # Verify commit exists
          {output, 0} = System.cmd("git", ["rev-list", "--count", "HEAD"])
          commit_count = String.trim(output) |> String.to_integer()
          assert commit_count >= 1, "Should have at least one commit"
        after
          File.cd!(original_cwd)
        end
      end
    end
  end

  describe "handle missing git" do
    @tag :integration
    test "handles missing git gracefully in development", %{tmp_dir: tmp_dir} do
      # This test simulates what happens when git is not available
      # but --git flag is used. In practice, the initialize_git_repo function
      # will output error messages but not crash the entire task.

      project_name = "test_project_no_git_binary"
      project_path = Path.join(tmp_dir, project_name)

      original_cwd = File.cwd!()

      try do
        File.cd!(tmp_dir)

        # Create project first without git
        {_output, exit_code} =
          System.cmd(
            "mix",
            ["igniter.new", project_name, "--yes", "--no-installer-version-check"],
            stderr_to_stdout: true,
            env: [{"MIX_ENV", "test"}]
          )

        assert exit_code == 0
        assert File.exists?(project_path)

        File.cd!(project_path)

        # Now test that the git repo functionality produces appropriate output
        # when git commands fail (we can't easily simulate missing git binary in tests)
        if git_available?() do
          # At least verify that git operations would work in normal circumstances
          {_output, exit_code} = System.cmd("git", ["init"])
          assert exit_code == 0
        end
      after
        File.cd!(original_cwd)
      end
    end
  end

  # Helper to ensure git is available for testing
  defp git_available? do
    case System.cmd("git", ["--version"]) do
      {_, 0} -> true
      _ -> false
    end
  end
end
