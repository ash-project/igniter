defmodule Igniter.Code.String do
  @moduledoc """
  Utilities for working with strings.
  """

  alias Sourceror.Zipper

  @doc "Returns true if the node represents a literal string, false otherwise."
  @spec string?(Zipper.t()) :: boolean()
  def string?(zipper) do
    case zipper.node do
      v when is_binary(v) ->
        true

      {:__block__, meta, [v]} when is_binary(v) ->
        is_binary(meta[:delimiter])

      _ ->
        false
    end
  end

  @doc "Updates a node representing a string with the result of the given function"
  @spec update_string(Zipper.t(), (String.t() -> {:ok, String.t()} | :error)) ::
          {:ok, Zipper.t()} | :error
  def update_string(zipper, func) do
    case zipper.node do
      v when is_binary(v) ->
        with {:ok, new_str} <- func.(v) do
          {:ok, Zipper.replace(zipper, new_str)}
        end

      {:__block__, meta, [v]} when is_binary(v) ->
        if is_binary(meta[:delimiter]) do
          with {:ok, new_str} <- func.(v) do
            {:ok, Zipper.replace(zipper, {:__block__, meta, [new_str]})}
          end
        else
          :error
        end

      _ ->
        :error
    end
  end
end
