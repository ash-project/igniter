defmodule Igniter.Project.TestTest do
  use ExUnit.Case

  alias Rewrite.Source

  describe "ensure_test_support" do
    test "it adds the path if it doesn't exist" do
      assert %{rewrite: rewrite} =
               Igniter.new()
               |> Igniter.include_existing_elixir_file("mix.exs")
               |> Map.update!(:rewrite, fn rewrite ->
                 source = Rewrite.source!(rewrite, "mix.exs")

                 source =
                   Source.update(source, :content, """
                    defmodule Igniter.MixProject do
                      use Mix.Project

                      def project do
                        [
                          app: :igniter
                        ]
                      end
                    end
                   """)

                 Rewrite.update!(rewrite, source)
               end)
               |> Igniter.Project.Test.ensure_test_support()

      contents =
        rewrite
        |> Rewrite.source!("mix.exs")
        |> Source.get(:content)

      assert String.contains?(contents, "elixirc_paths: elixirc_paths(Mix.env())")

      assert String.contains?(
               contents,
               """
               defp elixirc_paths(:test), do: elixirc_paths(:dev) ++ [\"test/support\"]\n  defp elixirc_paths(_), do: [\"lib\"]
               """
               |> String.trim()
             )
    end

    test "it doesnt change anything if the setting is already configured" do
      assert %{rewrite: rewrite} =
               Igniter.new()
               |> Igniter.include_existing_elixir_file("mix.exs")
               |> Map.update!(:rewrite, fn rewrite ->
                 source = Rewrite.source!(rewrite, "mix.exs")

                 source =
                   Source.update(source, :content, """
                    defmodule Igniter.MixProject do
                      use Mix.Project

                      def project do
                        [
                          app: :igniter,
                          elixirc_paths: ["foo/bar"]
                        ]
                      end
                    end
                   """)

                 Rewrite.update!(rewrite, source)
               end)
               |> Igniter.Project.Test.ensure_test_support()

      contents =
        rewrite
        |> Rewrite.source!("mix.exs")
        |> Source.get(:content)

      assert contents == """
             defmodule Igniter.MixProject do
               use Mix.Project

               def project do
                 [
                   app: :igniter,
                   elixirc_paths: ["foo/bar"]
                 ]
               end
             end
             """
    end
  end
end
