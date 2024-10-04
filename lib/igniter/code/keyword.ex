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
    if Common.node_matches_pattern?(zipper, value when is_list(value)) do
      case Igniter.Code.List.move_to_list_item(zipper, fn item ->
             if Igniter.Code.Tuple.tuple?(item) do
               case Igniter.Code.Tuple.tuple_elem(item, 0) do
                 {:ok, first_elem} ->
                   Common.nodes_equal?(first_elem, key)

                 :error ->
                   false
               end
             end
           end) do
        {:ok, zipper} ->
          case Igniter.Code.Tuple.tuple_elem(zipper, 1) do
            {:ok, second_elem} ->
              keyword_has_path?(second_elem, rest)

            _ ->
              false
          end

        _ ->
          false
      end
    else
      false
    end
  end

  @doc "Returns true if the node is a nested keyword list containing a value at the given path."
  @spec get_key(Zipper.t(), atom()) :: term()
  def get_key(zipper, key) do
    if Igniter.Code.List.list?(zipper) do
      case Igniter.Code.List.move_to_list_item(zipper, fn item ->
             if Igniter.Code.Tuple.tuple?(item) do
               case Igniter.Code.Tuple.tuple_elem(item, 0) do
                 {:ok, first_elem} ->
                   Common.nodes_equal?(first_elem, key)

                 :error ->
                   false
               end
             end
           end) do
        {:ok, zipper} ->
          case Igniter.Code.Tuple.tuple_elem(zipper, 1) do
            {:ok, second_elem} ->
              {:ok, second_elem}

            _ ->
              :error
          end

        _ ->
          :error
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

    Igniter.Code.Common.within(zipper, fn zipper ->
      do_put_in_keyword(zipper, path, value, updater)
    end)
  end

  defp do_put_in_keyword(zipper, [key], value, updater) do
    set_keyword_key(zipper, key, value, updater)
  end

  defp do_put_in_keyword(zipper, [key | rest], value, updater) do
    zipper = Common.maybe_move_to_single_child_block(zipper)

    if Igniter.Code.List.list?(zipper) do
      case Igniter.Code.List.move_to_list_item(zipper, fn item ->
             if Igniter.Code.Tuple.tuple?(item) do
               case Igniter.Code.Tuple.tuple_elem(item, 0) do
                 {:ok, first_elem} ->
                   Common.nodes_equal?(first_elem, key)

                 :error ->
                   false
               end
             end
           end) do
        :error ->
          value =
            keywordify(rest, value)

          value =
            value
            |> Sourceror.to_string()
            |> Sourceror.parse_string!()

          value = Common.use_aliases(value, zipper)

          to_append =
            case zipper.node do
              [{{:__block__, meta, _}, _} | _] ->
                if meta[:format] do
                  {{:__block__, [format: meta[:format]], [key]}, {:__block__, [], [value]}}
                else
                  {{:__block__, [], [key]}, {:__block__, [], [value]}}
                end

              [] ->
                {{:__block__, [format: :keyword], [key]}, {:__block__, [], [value]}}

              _current_node ->
                {{:__block__, [], [key]}, {:__block__, [], [value]}}
            end

          {:ok, Zipper.append_child(zipper, to_append)}

        {:ok, zipper} ->
          zipper
          |> Igniter.Code.Tuple.tuple_elem(1)
          |> case do
            {:ok, zipper} ->
              do_put_in_keyword(zipper, rest, value, updater)

            :error ->
              :error
          end
      end
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
    zipper = Common.maybe_move_to_single_child_block(zipper)

    if Igniter.Code.List.list?(zipper) do
      zipper = Common.maybe_move_to_single_child_block(zipper)

      case Igniter.Code.List.move_to_list_item(zipper, fn item ->
             if Igniter.Code.Tuple.tuple?(item) do
               case Igniter.Code.Tuple.tuple_elem(item, 0) do
                 {:ok, first_elem} ->
                   Common.nodes_equal?(first_elem, key)

                 :error ->
                   false
               end
             end
           end) do
        :error ->
          to_append =
            case zipper.node do
              [{{:__block__, meta, _}, _} | _] ->
                value =
                  value
                  |> Sourceror.to_string()
                  |> Sourceror.parse_string!()

                value = Common.use_aliases(value, zipper)

                if meta[:format] do
                  {{:__block__, [format: meta[:format]], [key]}, value}
                else
                  {{:__block__, [], [key]}, value}
                end

              [] ->
                {{:__block__, [format: :keyword], [key]}, {:__block__, [], [value]}}

              _ ->
                {key, value}
            end

          {:ok, Zipper.append_child(zipper, to_append)}

        {:ok, zipper} ->
          zipper
          |> Igniter.Code.Tuple.tuple_elem(1)
          |> case do
            {:ok, zipper} ->
              case updater.(zipper) do
                {:ok, zipper} -> {:ok, Zipper.replace(zipper, {:__block__, [], [zipper.node]})}
                :error -> :error
              end

            :error ->
              :error
          end
      end
    else
      :error
    end
  end

  @doc "Removes a key from a keyword list if present. Returns `:error` only if the node is not a list"
  @spec remove_keyword_key(Zipper.t(), atom()) :: {:ok, Zipper.t()} | :error
  def remove_keyword_key(zipper, key) do
    Common.within(zipper, fn zipper ->
      if Igniter.Code.List.list?(zipper) do
        case Igniter.Code.List.move_to_list_item(zipper, fn item ->
               if Igniter.Code.Tuple.tuple?(item) do
                 case Igniter.Code.Tuple.tuple_elem(item, 0) do
                   {:ok, first_elem} ->
                     Common.nodes_equal?(first_elem, key)

                   :error ->
                     false
                 end
               end
             end) do
          :error ->
            {:ok, zipper}

          {:ok, zipper} ->
            {:ok, zipper |> Zipper.remove()}
        end
      else
        :error
      end
    end)
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
