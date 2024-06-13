defmodule Igniter.Debug do
  @moduledoc "Tools for debugging zippers."
  alias Sourceror.Zipper

  @doc "Puts the formatted code at the node of the zipper to the console"
  def puts_code_at_node(zipper) do
    zipper
    |> Zipper.subtree()
    |> Zipper.root()
    |> Sourceror.to_string()
    |> then(&"==code==\n#{&1}\n==code==\n")
    |> IO.puts()

    zipper
  end

  @doc "Returns the formatted code at the node of the zipper to the console"
  def code_at_node(zipper) do
    zipper
    |> Zipper.subtree()
    |> Zipper.root()
    |> Sourceror.to_string()
  end

  @doc "Puts the ast at the node of the zipper to the console"
  def puts_ast_at_node(zipper) do
    zipper
    |> Zipper.subtree()
    |> Zipper.root()
    |> then(&"==ast==\n#{inspect(&1)}\n==ast==\n")
    |> IO.puts()

    zipper
  end
end
