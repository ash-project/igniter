defmodule Igniter.Util.Debug do
  @moduledoc "Tools for debugging zippers."
  alias Sourceror.Zipper

  @doc "Puts the formatted code at the node of the zipper to the console"
  def puts_code_at_node({:ok, zipper}) do
    zipper
    |> Zipper.node()
    |> Sourceror.to_string()
    |> then(&"==code==\n{:ok, #{&1}}\n==!code==\n")
    |> IO.puts()

    {:ok, zipper}
  end

  def puts_code_at_node(:error) do
    IO.puts("==code==\n:error\n==!code==\n")

    :error
  end

  def puts_code_at_node(zipper) do
    zipper
    |> Zipper.node()
    |> Sourceror.to_string()
    |> then(&"==code==\n#{&1}\n==!code==\n")
    |> IO.puts()

    zipper
  end

  @doc "Returns the formatted code at the node of the zipper to the console"
  def code_at_node(zipper) do
    zipper
    |> Zipper.node()
    |> Sourceror.to_string()
  end

  @doc "Puts the ast at the node of the zipper to the console"
  def puts_ast_at_node(zipper) do
    zipper
    |> Zipper.node()
    |> then(&"==ast==\n#{inspect(&1, pretty: true)}\n==!ast==\n")
    |> IO.puts()

    zipper
  end
end
