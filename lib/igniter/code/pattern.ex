# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Igniter.Code.Pattern do
  @moduledoc """
  Pattern-based AST navigation and rewriting powered by ExAST.

  Requires `{:ex_ast, "~> 0.5"}` (included as a dependency of Igniter).

  ## Pattern syntax

  Patterns are valid Elixir expressions:

  | Syntax | Meaning |
  |--------|---------|
  | `_` or `_name` | Wildcard — matches any node, not captured |
  | `name`, `expr` | Capture — matches any node, bound by name |
  | `...` | Ellipsis — matches zero or more nodes |
  | Everything else | Literal — must match exactly |

  Structs and maps match partially, pipes are normalized.

  ## Examples

      # Move to a node matching a pattern
      {:ok, zipper} = Pattern.move_to(zipper, "Repo.get!(_, _)")

      # Ellipsis — match any arity
      {:ok, zipper} = Pattern.move_to(zipper, "Logger.info(...)")

      # Check if current node matches
      Pattern.matches?(zipper, "use GenServer")

      # Find all matching nodes
      zippers = Pattern.find_all(zipper, "Repo.get!(...)")

      # Replace with captures
      {:ok, zipper} = Pattern.replace(zipper,
        "Enum.map(list, f)", "Enum.flat_map(list, f)")

      # Replace all occurrences
      {:ok, zipper} = Pattern.replace_all(zipper,
        "Logger.debug(msg, ...)", "Logger.warning(msg, ...)")

      # Context filters
      {:ok, zipper} = Pattern.move_to(zipper,
        "Repo.get!(...)", not_inside: "test _ do _ end")

      # Inside update_elixir_file
      Igniter.update_elixir_file(igniter, path, fn zipper ->
        Pattern.replace_all(zipper,
          "Enum.map(list, f)", "Enum.flat_map(list, f)")
      end)

      # Project-level: replace across all matching files
      Pattern.replace_in_all_files(igniter,
        "Logger.debug(msg, ...)", "Logger.warning(msg, ...)")

      # ~p sigil for compile-time pattern parsing
      import Igniter.Code.Pattern
      Pattern.find_all(zipper, ~p"Repo.get!(...)")
  """

  alias Sourceror.Zipper

  @type pattern :: String.t() | Macro.t()

  @doc """
  Parses a pattern string into AST at compile time.

  Avoids runtime string parsing. The result can be passed
  to any function in this module.

  ## Examples

      import Igniter.Code.Pattern

      Pattern.find_all(zipper, ~p"IO.inspect(...)")
      Pattern.replace_all(zipper, ~p"dbg(expr)", ~p"expr")
  """
  defmacro sigil_p({:<<>>, _, [string]}, _modifiers) when is_binary(string) do
    pattern = Code.string_to_quoted!(string)
    Macro.escape(pattern)
  end

  @doc """
  Returns `true` if the current node matches the pattern.

  Useful as a predicate inside `Igniter.Code.Common.move_to/2`,
  `find_all_matching_modules`, or similar callbacks.

  ## Examples

      Igniter.Code.Common.move_to(zipper, fn zipper ->
        Pattern.matches?(zipper, "use GenServer")
      end)
  """
  @spec matches?(Zipper.t(), pattern()) :: boolean()
  def matches?(%Zipper{} = zipper, pattern) do
    ExAST.Pattern.match(Zipper.node(zipper), pattern) != :error
  end

  @doc """
  Moves to the first node matching `pattern`.

  Returns `{:ok, zipper}` positioned at the matched node, or `:error`.

  ## Options

    * `:inside` — only match inside ancestors matching this pattern
    * `:not_inside` — skip matches inside ancestors matching this pattern
  """
  @spec move_to(Zipper.t(), pattern(), keyword()) :: {:ok, Zipper.t()} | :error
  def move_to(%Zipper{} = zipper, pattern, opts \\ []) do
    case do_find_all(zipper, pattern, opts) do
      [first | _] -> navigate_to(zipper, first.node)
      [] -> :error
    end
  end

  @doc """
  Returns a list of zippers, one for each node matching `pattern`.


  ## Options

    * `:inside` — only match inside ancestors matching this pattern
    * `:not_inside` — skip matches inside ancestors matching this pattern
  """
  @spec find_all(Zipper.t(), pattern(), keyword()) :: [Zipper.t()]
  def find_all(%Zipper{} = zipper, pattern, opts \\ []) do
    zipper
    |> do_find_all(pattern, opts)
    |> Enum.reduce([], fn match, acc ->
      case navigate_to(zipper, match.node) do
        {:ok, z} -> [z | acc]
        :error -> acc
      end
    end)
    |> Enum.reverse()
  end

  @doc """
  Replaces the first node matching `pattern` with `replacement`.

  Returns `{:ok, zipper}` with the modified tree, or `:error` if
  no match is found.

  ## Options

    * `:inside` — only match inside ancestors matching this pattern
    * `:not_inside` — skip matches inside ancestors matching this pattern
  """
  @spec replace(Zipper.t(), pattern(), pattern(), keyword()) ::
          {:ok, Zipper.t()} | :error
  def replace(%Zipper{} = zipper, pattern, replacement, opts \\ []) do
    case do_find_all(zipper, pattern, opts) do
      [first | _] -> do_replace_node(zipper, first.node, pattern, replacement)
      [] -> :error
    end
  end

  @doc """
  Replaces all nodes matching `pattern` with `replacement`.

  Returns `{:ok, zipper}` with the modified tree. If no matches
  are found, returns the zipper unchanged.

  ## Options

    * `:inside` — only match inside ancestors matching this pattern
    * `:not_inside` — skip matches inside ancestors matching this pattern
  """
  @spec replace_all(Zipper.t(), pattern(), pattern(), keyword()) ::
          {:ok, Zipper.t()} | :error
  def replace_all(%Zipper{} = zipper, pattern, replacement, opts \\ []) do
    root = Zipper.topmost_root(zipper)
    new_ast = ExAST.Patcher.replace_all(root, pattern, replacement, opts)
    {:ok, Zipper.zip(new_ast)}
  end

  @doc """
  Replaces all nodes matching `pattern` with `replacement` in a single file.

  Wraps `Igniter.update_elixir_file/3` with pattern-based replacement.

  ## Options

    * `:inside` — only match inside ancestors matching this pattern
    * `:not_inside` — skip matches inside ancestors matching this pattern
  """
  @spec replace_in_file(Igniter.t(), String.t(), pattern(), pattern(), keyword()) :: Igniter.t()
  def replace_in_file(igniter, path, pattern, replacement, opts \\ []) do
    Igniter.update_elixir_file(igniter, path, fn zipper ->
      replace_all(zipper, pattern, replacement, opts)
    end)
  end

  @doc """
  Replaces all nodes matching `pattern` with `replacement` across all
  Elixir files in the project.

  ## Options

    * `:inside` — only match inside ancestors matching this pattern
    * `:not_inside` — skip matches inside ancestors matching this pattern
  """
  @spec replace_in_all_files(Igniter.t(), pattern(), pattern(), keyword()) :: Igniter.t()
  def replace_in_all_files(igniter, pattern, replacement, opts \\ []) do
    igniter = Igniter.include_all_elixir_files(igniter)

    igniter.rewrite
    |> Rewrite.sources()
    |> Enum.filter(&elixir_source?/1)
    |> Enum.map(&Rewrite.Source.get(&1, :path))
    |> Enum.reduce(igniter, fn path, igniter ->
      replace_in_file(igniter, path, pattern, replacement, opts)
    end)
  end

  # --- Private ---

  defp do_find_all(zipper, pattern, opts) do
    ExAST.Patcher.find_all(zipper, pattern, opts)
  end

  defp do_replace_node(zipper, matched_node, pattern, replacement) do
    replacement_ast = to_quoted(replacement)

    case ExAST.Pattern.match(matched_node, pattern) do
      {:ok, captures} ->
        new_node =
          replacement_ast
          |> ExAST.Pattern.substitute(captures)
          |> restore_meta()

        case navigate_to(zipper, matched_node) do
          {:ok, z} -> {:ok, z |> Zipper.replace(new_node) |> Zipper.topmost()}
          :error -> :error
        end

      :error ->
        :error
    end
  end

  defp navigate_to(zipper, target_node) do
    zipper
    |> Zipper.topmost()
    |> Igniter.Code.Common.move_to(&(&1.node == target_node))
  end

  defp elixir_source?(source), do: match?(%Rewrite.Source{filetype: %Rewrite.Source.Ex{}}, source)

  defp to_quoted(pattern) when is_binary(pattern), do: Code.string_to_quoted!(pattern)
  defp to_quoted(pattern), do: pattern

  defp restore_meta(ast) do
    Macro.prewalk(ast, fn
      {form, nil, args} -> {form, [], args}
      other -> other
    end)
  end
end
