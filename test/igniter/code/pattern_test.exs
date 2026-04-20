# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Igniter.Code.PatternTest do
  use ExUnit.Case

  alias Igniter.Code.Pattern

  defp zip(code) do
    code
    |> Sourceror.parse_string!()
    |> Sourceror.Zipper.zip()
  end

  defp code_at(zipper), do: Igniter.Util.Debug.code_at_node(zipper)

  describe "available?/0" do
    test "returns true when ExAST is loaded" do
      assert Pattern.available?()
    end
  end

  describe "move_to/3" do
    test "moves to first matching node" do
      assert {:ok, zipper} =
               """
               Logger.info("hello")
               Enum.map(data, &to_string/1)
               """
               |> zip()
               |> Pattern.move_to("Enum.map(_, _)")

      assert code_at(zipper) =~ "Enum.map(data"
    end

    test "returns :error when no match" do
      assert :error =
               "Logger.info(:hello)"
               |> zip()
               |> Pattern.move_to("Enum.map(_, _)")
    end

    test "accepts quoted patterns" do
      assert {:ok, zipper} =
               "Enum.map(data, &to_string/1)"
               |> zip()
               |> Pattern.move_to(quote(do: Enum.map(_, _)))

      assert code_at(zipper) =~ "Enum.map"
    end

    test "respects inside option" do
      zipper =
        zip("""
        defmodule A do
          def run, do: Enum.map(a, &to_string/1)
          defp helper, do: Enum.map(b, &to_string/1)
        end
        """)

      assert {:ok, zipper} =
               Pattern.move_to(zipper, "Enum.map(_, _)", inside: "defp _ do _ end")

      assert code_at(zipper) =~ "Enum.map(b"
    end

    test "respects not_inside option" do
      zipper =
        zip("""
        defmodule A do
          def run, do: Enum.map(a, &to_string/1)

          test "example" do
            Enum.map(b, &to_string/1)
          end
        end
        """)

      assert {:ok, zipper} =
               Pattern.move_to(zipper, "Enum.map(_, _)", not_inside: "test _ do _ end")

      assert code_at(zipper) =~ "Enum.map(a"
    end
  end

  describe "find_all/3" do
    test "returns zippers for all matches" do
      zippers =
        """
        Enum.map(a, &to_string/1)
        Logger.info("hello")
        Enum.map(b, &to_string/1)
        """
        |> zip()
        |> Pattern.find_all("Enum.map(_, _)")

      assert length(zippers) == 2
      assert Enum.all?(zippers, &(code_at(&1) =~ "Enum.map"))
    end

    test "returns empty list when no match" do
      assert [] =
               "Logger.info(:hello)"
               |> zip()
               |> Pattern.find_all("Enum.map(_, _)")
    end

    test "accepts quoted patterns" do
      zippers =
        "Enum.map(data, &to_string/1)"
        |> zip()
        |> Pattern.find_all(quote(do: Enum.map(_, _)))

      assert [_] = zippers
    end

    test "respects inside filter" do
      zippers =
        """
        defmodule A do
          def run, do: Enum.map(a, &to_string/1)
          defp helper, do: Enum.map(b, &to_string/1)
        end
        """
        |> zip()
        |> Pattern.find_all("Enum.map(_, _)", inside: "defp _ do _ end")

      assert [z] = zippers
      assert code_at(z) =~ "Enum.map(b"
    end
  end

  describe "replace/4" do
    test "replaces first match" do
      assert {:ok, zipper} =
               """
               Enum.map(a, fun)
               Enum.map(b, fun)
               """
               |> zip()
               |> Pattern.replace("Enum.map(list, f)", "Enum.flat_map(list, f)")

      source = code_at(zipper)
      assert source =~ "Enum.flat_map(a"
      assert source =~ "Enum.map(b"
    end

    test "returns :error when no match" do
      assert :error =
               "Logger.info(:hello)"
               |> zip()
               |> Pattern.replace("Enum.map(list, f)", "Enum.flat_map(list, f)")
    end

    test "accepts quoted pattern and replacement" do
      assert {:ok, zipper} =
               "Enum.map(data, fun)"
               |> zip()
               |> Pattern.replace(
                 quote(do: Enum.map(list, f)),
                 quote(do: Enum.flat_map(list, f))
               )

      assert code_at(zipper) =~ "Enum.flat_map(data"
    end
  end

  describe "replace_all/4" do
    test "replaces all matches" do
      assert {:ok, zipper} =
               """
               Enum.map(a, fun)
               Logger.info("keep")
               Enum.map(b, fun)
               """
               |> zip()
               |> Pattern.replace_all("Enum.map(list, f)", "Enum.flat_map(list, f)")

      source = code_at(zipper)
      assert source =~ "Enum.flat_map(a"
      assert source =~ "Enum.flat_map(b"
      assert source =~ "Logger.info"
    end

    test "no match returns zipper unchanged" do
      zipper = zip("Logger.info(:hello)")

      assert {:ok, result} =
               Pattern.replace_all(zipper, "Enum.map(list, f)", "Enum.flat_map(list, f)")

      assert code_at(result) =~ "Logger.info(:hello)"
    end

    test "accepts quoted pattern and replacement" do
      assert {:ok, zipper} =
               "Enum.map(data, fun)"
               |> zip()
               |> Pattern.replace_all(
                 quote(do: Enum.map(list, f)),
                 quote(do: Enum.flat_map(list, f))
               )

      assert code_at(zipper) =~ "Enum.flat_map(data"
    end

    test "respects inside filter" do
      assert {:ok, zipper} =
               """
               defmodule A do
                 def run, do: Enum.map(a, fun)
                 defp helper, do: Enum.map(b, fun)
               end
               """
               |> zip()
               |> Pattern.replace_all("Enum.map(list, f)", "Enum.flat_map(list, f)",
                 inside: "defp _ do _ end"
               )

      root = Sourceror.Zipper.topmost_root(zipper)
      source = inspect(root, limit: :infinity)
      assert source =~ ":map"
      assert source =~ ":flat_map"
    end
  end

  describe "integration with update_elixir_file" do
    test "works inside Igniter pipeline" do
      igniter = Igniter.new()

      path = "lib/example.ex"

      igniter =
        Igniter.create_new_file(igniter, path, """
        defmodule Example do
          def run do
            Enum.map(data, &to_string/1)
            Logger.info("hello")
          end
        end
        """)

      igniter =
        Igniter.update_elixir_file(igniter, path, fn zipper ->
          Pattern.replace_all(zipper, "Enum.map(list, f)", "Enum.flat_map(list, f)")
        end)

      source = Rewrite.Source.get(Rewrite.source!(igniter.rewrite, path), :content)
      assert source =~ "Enum.flat_map(data"
      refute source =~ "Enum.map"
      assert source =~ "Logger.info"
    end
  end

  describe "ellipsis (...)" do
    test "move_to matches any arity" do
      assert {:ok, zipper} =
               """
               Logger.info("hello")
               Enum.reduce(list, 0, &+/2)
               """
               |> zip()
               |> Pattern.move_to("Enum.reduce(...)")

      assert code_at(zipper) =~ "Enum.reduce"
    end

    test "find_all with ellipsis matches multiple arities" do
      zippers =
        """
        Enum.map(a, fun)
        Logger.info("hello")
        Enum.map(b, fun, opts)
        """
        |> zip()
        |> Pattern.find_all("Enum.map(...)")

      assert length(zippers) == 2
    end

    test "replace_all with ellipsis in pattern" do
      assert {:ok, zipper} =
               """
               Logger.debug("a")
               Logger.debug("b", extra: true)
               Logger.info("keep")
               """
               |> zip()
               |> Pattern.replace_all("Logger.debug(msg, ...)", "Logger.warning(msg, ...)")

      source = code_at(zipper)
      assert source =~ "Logger.warning"
      assert source =~ "Logger.info"
      refute source =~ "Logger.debug"
    end

    test "move_to with def ... end" do
      assert {:ok, zipper} =
               """
               defmodule A do
                 def run(a, b) do
                   a + b
                 end
               end
               """
               |> zip()
               |> Pattern.move_to("def run(...) do ... end")

      assert code_at(zipper) =~ "def run"
    end
  end

  describe "matches?/2" do
    test "returns true when pattern matches current node" do
      zipper =
        """
        use GenServer
        """
        |> zip()

      assert Pattern.matches?(zipper, "use GenServer")
    end

    test "returns false when pattern does not match" do
      zipper = zip("use GenServer")
      refute Pattern.matches?(zipper, "use Supervisor")
    end

    test "works as predicate in Common.move_to" do
      assert {:ok, zipper} =
               """
               Logger.info("hello")
               use GenServer
               """
               |> zip()
               |> Igniter.Code.Common.move_to(&Pattern.matches?(&1, "use GenServer"))

      assert code_at(zipper) =~ "use GenServer"
    end

    test "works with ellipsis" do
      zipper = zip("Enum.map(a, b, c)")
      assert Pattern.matches?(zipper, "Enum.map(...)")
    end

    test "works with quoted" do
      zipper = zip("Enum.map(a, b)")
      assert Pattern.matches?(zipper, quote(do: Enum.map(_, _)))
    end
  end

  describe "replace_in_file/5" do
    test "replaces pattern in a single file" do
      igniter = Igniter.new()

      path = "lib/worker.ex"

      igniter =
        Igniter.create_new_file(igniter, path, """
        defmodule Worker do
          def run do
            Enum.map(data, &to_string/1)
          end
        end
        """)

      igniter =
        Pattern.replace_in_file(igniter, path, "Enum.map(list, f)", "Enum.flat_map(list, f)")

      source = Rewrite.Source.get(Rewrite.source!(igniter.rewrite, path), :content)
      assert source =~ "Enum.flat_map(data"
      refute source =~ "Enum.map"
    end
  end

  describe "replace_in_all_files/4" do
    test "replaces across multiple files" do
      igniter = Igniter.new()

      igniter =
        Igniter.create_new_file(igniter, "lib/a.ex", """
        defmodule A do
          def run, do: Enum.map(x, fun)
        end
        """)

      igniter =
        Igniter.create_new_file(igniter, "lib/b.ex", """
        defmodule B do
          def run, do: Enum.map(y, fun)
        end
        """)

      igniter =
        Pattern.replace_in_all_files(igniter, "Enum.map(list, f)", "Enum.flat_map(list, f)")

      source_a = Rewrite.Source.get(Rewrite.source!(igniter.rewrite, "lib/a.ex"), :content)
      source_b = Rewrite.Source.get(Rewrite.source!(igniter.rewrite, "lib/b.ex"), :content)
      assert source_a =~ "Enum.flat_map"
      assert source_b =~ "Enum.flat_map"
    end
  end

  describe "~p sigil" do
    import Igniter.Code.Pattern

    test "parses pattern at compile time" do
      assert {:ok, zipper} =
               "Enum.map(data, fun)"
               |> zip()
               |> Pattern.move_to(~p"Enum.map(_, _)")

      assert code_at(zipper) =~ "Enum.map"
    end

    test "works with ellipsis" do
      zippers =
        """
        Enum.map(a, fun)
        Enum.reduce(b, 0, fun)
        """
        |> zip()
        |> Pattern.find_all(~p"Enum.map(...)")

      assert [_] = zippers
    end

    test "works with replace_all" do
      assert {:ok, zipper} =
               "Enum.map(data, fun)"
               |> zip()
               |> Pattern.replace_all(~p"Enum.map(list, f)", ~p"Enum.flat_map(list, f)")

      assert code_at(zipper) =~ "Enum.flat_map"
    end
  end
end
