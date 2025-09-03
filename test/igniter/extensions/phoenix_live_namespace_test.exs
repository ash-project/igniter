defmodule Igniter.Extensions.PhoenixLiveNamespaceTest do
  use ExUnit.Case
  import Igniter.Test

  @moduledoc """
  Tests for fixing the Live namespace duplication bug.
  
  References:
  - Issue: https://github.com/ash-project/igniter/issues/329
  - PR: [To be added after PR creation]
  
  The bug: When creating modules with "Live" as a namespace segment (e.g., MyApp.Live.Dashboard.TestLive),
  the Phoenix extension incorrectly duplicates the "live" directory in the file path, creating
  `lib/my_app/live/live/dashboard/test_live.ex` instead of `lib/my_app/live/dashboard/test_live.ex`.
  """

  describe "Live namespace handling" do
    test "does not duplicate 'live' directory for modules with Live namespace segment" do
      # This reproduces the issue from https://github.com/ash-project/igniter/issues/329
      # When a module has "Live" as a namespace segment (e.g., MyApp.Live.Dashboard.TestLive),
      # it should NOT create a duplicated live/live directory structure
      
      igniter =
        test_project()
        |> Igniter.Project.IgniterConfig.add_extension(Igniter.Extensions.Phoenix)
      
      # Create a module with "Live" as a namespace segment
      module_name = MyApp.Live.Dashboard.TestLive
      
      igniter = 
        Igniter.Project.Module.create_module(igniter, module_name, """
        @moduledoc "Test module to demonstrate Igniter path bug fix"
        def hello, do: :world
        """)
      
      # Find the created module to verify its path
      {:ok, {_igniter, source, _zipper}} = 
        Igniter.Project.Module.find_module(igniter, module_name)
      
      actual_path = Rewrite.Source.get(source, :path)
      
      # The path should NOT contain duplicate "live/live" directories
      refute actual_path =~ ~r/live\/live/,
        "Module path should not contain duplicate 'live/live' directories. Got: #{actual_path}"
      
      # The correct path should be lib/my_app/live/dashboard/test_live.ex
      assert actual_path == "lib/my_app/live/dashboard/test_live.ex"
    end

    test "correctly handles LiveView modules with Web prefix" do
      # This ensures that genuine LiveView modules (MyAppWeb.*Live) still work correctly
      igniter =
        test_project()
        |> Igniter.Project.IgniterConfig.add_extension(Igniter.Extensions.Phoenix)
      
      module_name = TestWeb.Dashboard.TestLive
      
      igniter = 
        Igniter.Project.Module.create_module(igniter, module_name, """
        use TestWeb, :live_view
        
        def render(assigns) do
          ~H"<div>Test</div>"
        end
        """)
      
      {:ok, {_igniter, source, _zipper}} = 
        Igniter.Project.Module.find_module(igniter, module_name)
      
      actual_path = Rewrite.Source.get(source, :path)
      
      # Web-prefixed LiveView modules should go in the live directory
      assert actual_path == "lib/test_web/live/dashboard/test_live.ex"
    end

    test "handles nested Live namespace segments correctly" do
      # Test that MyAppWeb.Live.Components.ModalLive works correctly
      igniter =
        test_project()
        |> Igniter.Project.IgniterConfig.add_extension(Igniter.Extensions.Phoenix)
      
      module_name = TestWeb.Live.Components.ModalLive
      
      igniter = 
        Igniter.Project.Module.create_module(igniter, module_name, """
        use TestWeb, :live_component
        
        def render(assigns) do
          ~H"<div>Modal</div>"
        end
        """)
      
      {:ok, {_igniter, source, _zipper}} = 
        Igniter.Project.Module.find_module(igniter, module_name)
      
      actual_path = Rewrite.Source.get(source, :path)
      
      # Should handle nested Live segments properly
      assert actual_path == "lib/test_web/live/live/components/modal_live.ex"
    end

    test "minimal test case from issue #329" do
      # Direct test case from the issue report
      igniter = 
        test_project()
        |> Igniter.Project.IgniterConfig.add_extension(Igniter.Extensions.Phoenix)

      module_name = MyApp.Live.Dashboard.TestLive
      module_content = """
      @moduledoc "Test module to demonstrate Igniter path bug"
      def hello, do: :world
      """

      igniter = Igniter.Project.Module.create_module(igniter, module_name, module_content)

      case Igniter.Project.Module.find_module(igniter, module_name) do
        {:ok, {_igniter, source, _zipper}} ->
          actual_path = Rewrite.Source.get(source, :path)
          expected_path = "lib/my_app/live/dashboard/test_live.ex"

          # This assertion should pass with the fix
          refute actual_path =~ ~r/live\/live/,
            "Path contains duplicate 'live/live' directories: #{actual_path}"
          
          assert actual_path == expected_path,
            "Expected path: #{expected_path}, got: #{actual_path}"

        {:error, _} ->
          flunk("Failed to find created module")
      end
    end
  end
end