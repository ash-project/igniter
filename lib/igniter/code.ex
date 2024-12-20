defmodule Igniter.Code do
  @moduledoc """
  A struct used to patch code.

  Generally speaking, `t:Igniter.Code.t/0` structs should be created using
  helpers such as `from_string!/1`, `quoted/1`, and `escaped/1`.
  """

  @enforce_keys [:ast]
  defstruct [:ast]

  @type t :: %__MODULE__{ast: Macro.t()}

  @doc """
  Creates a code struct by parsing a string of source code.

  This function raises if the source code cannot be parsed to a valid ast.

  ## Examples

      iex> code = Igniter.Code.from_string!("foo(bar)")
      iex> {:foo, _, [{:bar, _, nil}]} = code.ast

      iex> assert_raise SyntaxError, fn ->
      ...>   Igniter.Code.from_string!("++")
      ...> end

  """
  @spec from_string!(source :: String.t()) :: t()
  def from_string!(source) when is_binary(source) do
    %__MODULE__{ast: Sourceror.parse_string!(source)}
  end

  @doc """
  Creates a code struct from an AST node.

  This function performs no additional validation on the AST.

  ## Examples

      iex> ast = {:__block__, [], ["my value"]}
      iex> code = Igniter.Code.quoted(ast)
      iex> code.ast == ast
      true

  """
  @spec quoted(ast :: Macro.t()) :: t()
  def quoted(ast) do
    %__MODULE__{ast: ast}
  end

  @doc """
  Creates a code struct from an AST node, raising if it is invalid.

  ## Examples

      iex> ast = {:__block__, [], ["my value"]}
      iex> code = Igniter.Code.quoted!(ast)
      iex> code.ast == ast
      true

      iex> invalid_ast = {:invalid_ast}
      iex> assert_raise ArgumentError, fn ->
      ...>   Igniter.Code.quoted!(invalid_ast)
      ...> end

  """
  @spec quoted!(ast :: Macro.t()) :: t()
  def quoted!(ast) do
    case Macro.validate(ast) do
      :ok ->
        quoted(ast)

      {:error, invalid} ->
        raise ArgumentError, """
        invalid AST:

            #{inspect(invalid)}

        found in expression:

            #{inspect(ast)}
        """
    end
  end

  @doc """
  Creates a code struct from a value that is recursively escaped.

  This can be used to turn values like maps, which are not valid quoted
  forms by themselves, into an AST.

  ## Examples

      iex> code = Igniter.Code.escaped(%{foo: 1})
      iex> {:%{}, _, [{:foo, 1}]} = code.ast

  """
  @spec escaped(value :: term()) :: t()
  def escaped(value) do
    value |> Macro.escape() |> quoted()
  end
end
