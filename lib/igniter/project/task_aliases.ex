defmodule Igniter.Project.TaskAliases do
  @moduledoc "Codemods and utilities for interacting with task aliases in the mix.exs file"

  @doc """
  Adds an alias to the mix.exs file

  # Options

  - `:if_exists` - How to alter the alias if it already exists. Options are:
    - `:ignore` - Do nothing if the alias already exists. This is the default.
    - `:prepend` - Add the new alias to the beginning of the list.
    - `{:prepend, value}` - Add a different value than the originally supplied alias to the beginning of the list.
    - `:append` - Add the new alias to the end of the list.
    - `{:append, value}` - Add a different value than the originally supplied alias to the end of the list.
    - `:warn` - Print a warning if the alias already exists.
  """
  @spec add_alias(
          Igniter.t(),
          atom() | String.t(),
          String.t() | list(String.t()),
          opts :: Keyword.t()
        ) :: Igniter.t()
  def add_alias(igniter, name, value, opts \\ []) do
    alter =
      case Keyword.get(opts, :if_exists, :ignore) do
        :append -> {:append, value}
        :prepend -> {:prepend, value}
        other -> other
      end

    name =
      if is_binary(name) do
        String.to_atom(name)
      else
        name
      end

    igniter
    |> Igniter.update_elixir_file("mix.exs", fn zipper ->
      case go_to_aliases(zipper) do
        {:ok, zipper} ->
          case alter do
            {prepend_or_append, add_value} when prepend_or_append in [:prepend, :append] ->
              case Igniter.Code.Keyword.set_keyword_key(
                     zipper,
                     name,
                     value,
                     &prepend_or_append(&1, add_value, prepend_or_append)
                   ) do
                {:ok, zipper} ->
                  {:ok, zipper}

                :error ->
                  {:warning,
                   """
                   Could not modify mix task aliases. Attempted to alias `#{name}` to:

                       #{Sourceror.to_string(value)}

                   Please manually modify your `mix.exs` file accordingly.
                   """}
              end

            other ->
              case Igniter.Code.Keyword.get_key(zipper, name) do
                {:ok, _} ->
                  case other do
                    :ignore ->
                      {:ok, zipper}

                    :warn ->
                      {:warning,
                       """
                       Could not add alias for `#{name}` in `mix.exs` because it already exists. Attempted to alias it to:

                          #{Sourceror.to_string(value)}
                       """}
                  end

                :error ->
                  case Igniter.Code.Keyword.set_keyword_key(zipper, name, value, &{:ok, &1}) do
                    {:ok, zipper} ->
                      {:ok, zipper}

                    :error ->
                      {:warning,
                       """
                       Could not modify mix task aliases. Attempted to alias `#{name}` to:

                           #{Sourceror.to_string(value)}

                       Please manually modify your `mix.exs` file accordingly.
                       """}
                  end
              end
          end

        :error ->
          {:warning,
           """
           Could not modify mix task aliases. Attempted to alias `#{name}` to:

               #{Sourceror.to_string(value)}

           Please manually modify your `mix.exs` file accordingly.
           """}
      end
    end)
  end

  @doc "Modifies an existing alias, doing nothing if it doesn't exist"
  @spec modify_existing_alias(
          Igniter.t(),
          atom() | String.t(),
          (Sourceror.Zipper.t() ->
             {:ok, Sourceror.Zipper.t()} | :error)
        ) :: Igniter.t()
  def modify_existing_alias(igniter, name, updater) do
    igniter
    |> Igniter.update_elixir_file("mix.exs", fn zipper ->
      name =
        if is_binary(name) do
          String.to_atom(name)
        else
          name
        end

      case go_to_aliases(zipper) do
        {:ok, zipper} ->
          case Igniter.Code.Keyword.get_key(zipper, name) do
            {:ok, zipper} ->
              updater.(zipper)

            :error ->
              zipper
          end

        :error ->
          zipper
      end
    end)
  end

  defp prepend_or_append(zipper, value, prepend_or_append) when is_list(value) do
    if prepend_or_append == :prepend do
      Enum.reverse(value)
    else
      value
    end
    |> Enum.reduce_while({:ok, zipper}, fn value, {:ok, zipper} ->
      case prepend_or_append(zipper, value, prepend_or_append) do
        {:ok, zipper} -> {:cont, {:ok, zipper}}
        :error -> {:halt, :error}
      end
    end)
  end

  defp prepend_or_append(zipper, value, :append) do
    zipper =
      if Igniter.Code.List.list?(zipper) do
        zipper
      else
        Igniter.Code.Common.replace_code(zipper, [zipper.node])
      end

    Igniter.Code.List.append_new_to_list(zipper, value)
  end

  defp prepend_or_append(zipper, value, :prepend) do
    zipper =
      if Igniter.Code.List.list?(zipper) do
        zipper
      else
        Igniter.Code.Common.replace_code(zipper, [zipper.node])
      end

    Igniter.Code.List.prepend_new_to_list(zipper, value)
  end

  defp go_to_aliases(zipper) do
    with {:ok, zipper} <- Igniter.Code.Function.move_to_defp(zipper, :aliases, 0),
         zipper <- Igniter.Code.Common.rightmost(zipper),
         true <- Igniter.Code.List.list?(zipper) do
      {:ok, zipper}
    else
      _ ->
        with {:ok, zipper} <- Igniter.Code.Function.move_to_def(zipper, :project, 0),
             zipper <- Igniter.Code.Common.rightmost(zipper),
             true <- Igniter.Code.List.list?(zipper),
             {:aliases_key, _zipper, {:ok, zipper}} <-
               {:aliases_key, zipper, Igniter.Code.Keyword.get_key(zipper, :aliases)},
             {:aliases_is_list?, zipper, true} <-
               {:aliases_is_list?, zipper, Igniter.Code.List.list?(zipper)} do
          {:ok, zipper}
        else
          {:aliases_key, zipper, :error} ->
            with {:ok, zipper} <-
                   Igniter.Code.Keyword.set_keyword_key(
                     zipper,
                     :aliases,
                     quote do
                       aliases()
                     end,
                     &{:ok, &1}
                   ),
                 {:ok, zipper} <-
                   Igniter.Code.Common.move_upwards(
                     zipper,
                     &Igniter.Code.Function.function_call?(&1, :defmodule)
                   ),
                 {:ok, zipper} <- Igniter.Code.Common.move_to_do_block(zipper) do
              zipper
              |> Igniter.Code.Common.add_code("""
              defp aliases() do
                []
              end
              """)
              |> go_to_aliases()
            else
              _ ->
                :error
            end

          {:aliases_is_list?, zipper, false} ->
            if Igniter.Code.Function.function_call?(zipper) do
              case Igniter.Code.Function.get_local_function_call_name(zipper) do
                {:ok, name} ->
                  with {:ok, zipper} <-
                         Igniter.Code.Common.move_upwards(
                           zipper,
                           &Igniter.Code.Function.function_call?(&1, :defmodule)
                         ),
                       {:ok, zipper} <- Igniter.Code.Common.move_to_do_block(zipper),
                       {:ok, zipper} <- Igniter.Code.Function.move_to_defp(zipper, name, 0),
                       zipper <- Igniter.Code.Common.rightmost(zipper),
                       true <- Igniter.Code.List.list?(zipper) do
                    {:ok, zipper}
                  else
                    _ ->
                      :error
                  end

                :error ->
                  :error
              end
            else
              :error
            end

          _ ->
            :error
        end
    end
  end
end
