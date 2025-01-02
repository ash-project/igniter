defmodule Igniter.Code.Keyword do
  @moduledoc """
  Utilities for working with keyword.
  """
  require Igniter.Code.Common
  alias Igniter.Code.Common
  alias Sourceror.Zipper

  @doc "Returns true if the node is a nested keyword list containing a value at the given path."
  @spec keyword_has_path?(Zipper.t(), [atom()]) :: boolean()
  def keyword_has_path?(_zipper, []), do: true

  def keyword_has_path?(zipper, [key | rest]) do
    case get_key(zipper, key) do
      {:ok, zipper} -> keyword_has_path?(zipper, rest)
      :error -> false
    end
  end

  @doc "Moves the zipper to the value of `key` in a keyword list."
  @spec get_key(Zipper.t(), atom()) :: {:ok, Zipper.t()} | :error
  def get_key(zipper, key) do
    zipper = Common.maybe_move_to_single_child_block(zipper)

    if Igniter.Code.List.list?(zipper) do
      item =
        Igniter.Code.List.move_to_list_item(zipper, fn item ->
          if Igniter.Code.Tuple.tuple?(item) do
            case Igniter.Code.Tuple.tuple_elem(item, 0) do
              {:ok, first_elem} ->
                Common.nodes_equal?(first_elem, key)

              :error ->
                false
            end
          end
        end)

      case item do
        {:ok, zipper} -> Igniter.Code.Tuple.tuple_elem(zipper, 1)
        :error -> :error
      end
    else
      :error
    end
  end

  @doc "Puts a value at a path into a keyword, calling `updater` on the zipper at the value if the key is already present"
  @spec put_in_keyword(
          Zipper.t(),
          list(atom()),
          term(),
          (Zipper.t() -> {:ok, Zipper.t()} | :error) | nil
        ) ::
          {:ok, Zipper.t()} | :error
  def put_in_keyword(zipper, path, value, updater \\ nil) do
    updater = updater || fn zipper -> {:ok, Common.replace_code(zipper, value)} end

    Common.within(zipper, fn zipper ->
      do_put_in_keyword(zipper, path, value, updater)
    end)
  end

  defp do_put_in_keyword(zipper, [key], value, updater) do
    set_keyword_key(zipper, key, value, updater)
  end

  defp do_put_in_keyword(zipper, [key | rest], value, updater) do
    case create_or_move_to_value_for_key(zipper, key) do
      {:found, zipper} ->
        do_put_in_keyword(zipper, rest, value, updater)

      {:new, zipper} ->
        {:ok, set_keyword_value!(zipper, keywordify(rest, value))}

      :error ->
        :error
    end
  end

  @spec set_keyword_key(
          Zipper.t(),
          atom(),
          term(),
          (Zipper.t() -> {:ok, Zipper.t()} | :error) | nil
        ) ::
          {:ok, Zipper.t()} | :error
  def set_keyword_key(zipper, key, value, updater \\ nil) do
    updater = updater || (&{:ok, &1})

    Common.within(zipper, fn zipper ->
      case create_or_move_to_value_for_key(zipper, key) do
        {:found, zipper} ->
          case updater.(zipper) do
            {:ok, zipper} ->
              {:ok, %{zipper | node: {:__block__, [], [zipper.node]}}}

            :error ->
              :error
          end

        {:new, zipper} ->
          {:ok, set_keyword_value!(zipper, value)}

        :error ->
          :error
      end
    end)
  end

  defp set_keyword_value!(zipper, value) do
    value =
      value
      |> Sourceror.to_string()
      |> Sourceror.parse_string!()
      |> Common.use_aliases(zipper)

    Zipper.replace(zipper, value)
  end

  @spec create_or_move_to_value_for_key(Zipper.t(), atom()) ::
          {:found, Zipper.t()} | {:new, Zipper.t()} | :error
  defp create_or_move_to_value_for_key(zipper, key) do
    zipper = Common.maybe_move_to_single_child_block(zipper)

    if Igniter.Code.List.list?(zipper) do
      case get_key(zipper, key) do
        {:ok, zipper} ->
          {:found, zipper}

        :error ->
          to_append =
            case zipper.node do
              [{{:__block__, meta, _}, _} | _] ->
                if meta[:format] do
                  {{:__block__, [format: meta[:format]], [key]}, {:__block__, [], [nil]}}
                else
                  {{:__block__, [], [key]}, {:__block__, [], [nil]}}
                end

              [] ->
                {{:__block__, [format: :keyword], [key]}, {:__block__, [], [nil]}}

              _current_node ->
                {{:__block__, [], [key]}, {:__block__, [], [nil]}}
            end

          {:ok, zipper} =
            zipper
            |> Zipper.append_child(to_append)
            |> get_key(key)

          {:new, zipper}
      end
    else
      :error
    end
  end

  @doc "Removes a key from a keyword list if present. Returns `:error` only if the node is not a list"
  @spec remove_keyword_key(Zipper.t(), atom()) :: {:ok, Zipper.t()} | :error
  def remove_keyword_key(zipper, key) do
    if Igniter.Code.List.list?(zipper) do
      Common.within(zipper, fn zipper ->
        case get_key(zipper, key) do
          {:ok, zipper} ->
            {:ok, zipper |> Zipper.up() |> Zipper.remove()}

          :error ->
            {:ok, zipper}
        end
      end)
    else
      :error
    end
  end

  @doc "Puts into nested keyword lists represented by `path`"
  @spec keywordify(path :: [atom()], value :: any()) :: any()
  def keywordify([], value) when is_integer(value) or is_float(value) do
    {:__block__, [token: to_string(value)], [value]}
  end

  def keywordify([], value) do
    {:__block__, [], [value]}
  end

  def keywordify([key | rest], value) do
    [{{:__block__, [format: :keyword], [key]}, {:__block__, [], [keywordify(rest, value)]}}]
  end
end
