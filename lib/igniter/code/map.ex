defmodule Igniter.Code.Map do
  @moduledoc """
  Utilities for working with maps.
  """

  require Igniter.Code.Common
  alias Igniter.Code.Common
  alias Sourceror.Zipper

  @doc "Puts a value at a path into a map, calling `updater` on the zipper at the value if the key is already present"
  @spec put_in_map(
          Zipper.t(),
          list(term()),
          term(),
          (Zipper.t() -> {:ok, Zipper.t()} | :error) | nil
        ) ::
          {:ok, Zipper.t()} | :error
  def put_in_map(zipper, path, value, updater \\ nil) do
    updater = updater || fn zipper -> {:ok, Common.replace_code(zipper, value)} end

    do_put_in_map(zipper, path, value, updater)
  end

  defp do_put_in_map(zipper, [key], value, updater) do
    set_map_key(zipper, key, value, updater)
  end

  defp do_put_in_map(zipper, [key | rest], value, updater) do
    cond do
      Common.node_matches_pattern?(zipper, {:%{}, _, []}) ->
        value = Common.use_aliases(value, zipper)

        {:ok,
         Zipper.append_child(
           zipper,
           mappify([key | rest], value)
         )}

      Common.node_matches_pattern?(zipper, {:%{}, _, _}) ->
        zipper
        |> Zipper.down()
        |> Igniter.Code.List.move_to_list_item(fn item ->
          if Igniter.Code.Tuple.tuple?(item) do
            case Igniter.Code.Tuple.tuple_elem(item, 0) do
              {:ok, first_elem} ->
                Common.nodes_equal?(first_elem, key)

              :error ->
                false
            end
          end
        end)
        |> case do
          :error ->
            value = Common.use_aliases(value, zipper)
            format = map_keys_format(zipper)
            value = mappify(rest, value)

            {:ok,
             Zipper.append_child(
               zipper,
               {{:__block__, [format: format], [key]}, {:__block__, [], [value]}}
             )}

          {:ok, zipper} ->
            zipper
            |> Igniter.Code.Tuple.tuple_elem(1)
            |> case do
              {:ok, zipper} ->
                do_put_in_map(zipper, rest, value, updater)

              :error ->
                :error
            end
        end

      true ->
        :error
    end
  end

  @doc "Puts a key into a map, calling `updater` on the zipper at the value if the key is already present"
  @spec set_map_key(Zipper.t(), term(), term(), (Zipper.t() -> {:ok, Zipper.t()} | :error)) ::
          {:ok, Zipper.t()} | :error
  def set_map_key(zipper, key, value, updater) do
    cond do
      Common.node_matches_pattern?(zipper, {:%{}, _, []}) ->
        value = Common.use_aliases(value, zipper)

        {:ok,
         Zipper.append_child(
           zipper,
           mappify([key], value)
         )}

      Common.node_matches_pattern?(zipper, {:%{}, _, _}) ->
        zipper
        |> Zipper.down()
        |> Common.move_right(fn item ->
          if Igniter.Code.Tuple.tuple?(item) do
            case Igniter.Code.Tuple.tuple_elem(item, 0) do
              {:ok, first_elem} ->
                Common.nodes_equal?(first_elem, key)

              :error ->
                false
            end
          end
        end)
        |> case do
          :error ->
            value = Common.use_aliases(value, zipper)
            format = map_keys_format(zipper)

            {:ok,
             Zipper.append_child(
               zipper,
               {{:__block__, [format: format], [key]}, {:__block__, [], [value]}}
             )}

          {:ok, zipper} ->
            zipper
            |> Igniter.Code.Tuple.tuple_elem(1)
            |> case do
              {:ok, zipper} ->
                updater.(zipper)

              :error ->
                :error
            end
        end

      true ->
        :error
    end
  end

  defp map_keys_format(zipper) do
    case zipper.node do
      value when is_list(value) ->
        Enum.all?(value, fn
          {:__block__, meta, _} ->
            meta[:format] == :keyword

          _ ->
            false
        end)
        |> case do
          true ->
            :keyword

          false ->
            :map
        end

      _ ->
        :map
    end
  end

  @doc "Puts a value into nested maps at the given path"
  def mappify([], value) do
    value
  end

  def mappify([key | rest], value) do
    format =
      if is_atom(key) do
        :keyword
      else
        :map
      end

    {:%{}, [], [{{:__block__, [format: format], [key]}, mappify(rest, value)}]}
  end
end
