# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule Igniter.Project.MixProject do
  @moduledoc """
  Codemods and utilities for updating project configuration in mix.exs.
  """

  require Igniter.Code.Common
  alias Igniter.Code.Common
  alias Sourceror.Zipper

  @doc """
  Updates the project configuration AST at the given path.

  This function accepts a `function_name` atom corresponding to a function
  like `project/0`, `application/0`, or `cli/0` and navigates to the given
  path, jumping to private functions if necessary and creating nested
  keyword lists if they don't already exist. It then calls the given
  `update_fun`, using the return value to update the AST.

  `update_fun` must be a function that accepts one argument, a zipper
  targeting the current AST at the given configuration path or `nil` if
  there was no value at that path. It then must return one of the
  following:

    * `{:ok, zipper}` - the updated zipper
    * `{:ok, {:code, quoted}}` - a quoted expression that should be
      inserted as the new value at `path`
    * `{:ok, nil}` - indicates that the last key in `path` should be
      removed
    * `{:error, message}` or `{:warning, message}` - an error or warning
      that should be added to `igniter`
    * `:error` - indicates `igniter` should be returned without change

  ## Examples

  Assuming a newly-generated Mix project that looks like:

      defmodule Example.MixProject do
        use Mix.Project

        def project do
          [
            app: :example,
            version: "0.1.0",
            elixir: "~> 1.17",
            start_permanent: Mix.env() == :prod,
            deps: deps()
          ]
        end

        def application do
          [
            extra_applications: [:logger]
          ]
        end

        defp deps do
          []
        end
      end

  ### Increment the project version by one patch level

      Igniter.Project.MixProject.update(igniter, :project, [:version], fn zipper ->
        new_version =
          zipper.node
          |> Version.parse!()
          |> Map.update!(:patch, &(&1 + 1))
          |> to_string()

        {:ok, {:code, new_version}}
      end)

      # would result in
      def project do
        [
          ...,
          version: "0.1.1",
          ...
        ]
      end

  ### Set the preferred env for a task to `:test`

      Igniter.Project.MixProject.update(
        igniter,
        :cli,
        [:preferred_envs, :"some.task"],
        fn _ -> {:ok, {:code, :test}} end
      )

      # would create `cli/0` and set the env:
      def cli do
        [
          preferred_envs: [
            "some.task": :test
          ]
        ]
      end

  ### Add `:some_application` to `:extra_applications`

      Igniter.Project.MixProject.update(igniter, :application, [:extra_applications], fn
        nil -> {:ok, {:code, [:some_application]}}
        zipper -> Igniter.Code.List.append_to_list(zipper, :some_application)
      end)

      # would result in
      def application do
        [
          extra_applications: [:logger, :some_application]
        ]
      end

  ### Remove `:extra_applications` altogether

      Igniter.Project.MixProject.update(
        igniter,
        :application,
        [:extra_applications],
        fn _ -> {:ok, nil} end
      )

      # would result in
      def application do
        []
      end

  """
  @spec update(
          Igniter.t(),
          function_name :: atom(),
          path :: [atom(), ...],
          update_fun ::
            (Zipper.t() | nil ->
               {:ok, Zipper.t() | nil | {:code, quoted :: Macro.t()}}
               | {:error | :warning, term()}
               | :error)
        ) :: Igniter.t()
  def update(%Igniter{} = igniter, function_name, path, update_fun)
      when is_atom(function_name) and is_function(update_fun, 1) do
    path = ensure_path!(path)

    Igniter.update_elixir_file(igniter, "mix.exs", fn zipper ->
      with {:ok, zipper} <- move_to_or_create_def_0(zipper, function_name),
           zipper <- resolve_to_config(zipper),
           {:ok, zipper} <- build_and_resolve_path(zipper, path) do
        update_resolved(zipper, update_fun)
      else
        :error ->
          {:error, "Unable to update mix.exs config for #{function_name}/0: #{inspect(path)}"}
      end
    end)
  end

  defp move_to_or_create_def_0(zipper, function_name) do
    case Igniter.Code.Function.move_to_def(zipper, function_name, 0) do
      {:ok, zipper} ->
        {:ok, zipper}

      :error ->
        zipper
        |> get_last_def()
        |> Common.add_code("""
        def #{function_name} do
          [
          ]
        end
        """)
        |> Igniter.Code.Function.move_to_def(function_name, 0)
    end
  end

  defp get_last_def(zipper, last \\ nil) do
    with {:ok, zipper} <- Igniter.Code.Function.move_to_def(zipper),
         {:ok, next} <- Common.move_right(zipper, 1) do
      get_last_def(next, zipper)
    else
      _ -> last
    end
  end

  defp build_and_resolve_path(zipper, []), do: {:ok, zipper}

  defp build_and_resolve_path(zipper, [key | rest]) do
    with {:ok, zipper} <- ensure_key(zipper, key) do
      zipper
      |> resolve_to_config()
      |> build_and_resolve_path(rest)
    end
  end

  defp resolve_to_config(zipper) do
    zipper
    |> Common.maybe_move_to_single_child_block()
    |> maybe_resolve_local_function_call()
    |> maybe_resolve_module_attribute()
    |> maybe_resolve_block_to_last_child()
  end

  defp maybe_resolve_local_function_call(zipper) do
    with {:ok, {name, arity}} <- Igniter.Code.Function.get_local_function_call(zipper),
         {:ok, zipper} <-
           Common.move_upwards(zipper, &Common.node_matches_pattern?(&1, {:defmodule, _, _})),
         {:ok, zipper} <- move_to_function_def(zipper, name, arity) do
      resolve_to_config(zipper)
    else
      _ -> zipper
    end
  end

  defp maybe_resolve_module_attribute(%Zipper{node: {:@, _, [{attr, _, nil}]}} = zipper) do
    case Common.find_prev(zipper, &Common.node_matches_pattern?(&1, {:@, _, [{^attr, _, [_]}]})) do
      {:ok, zipper} -> zipper |> Zipper.down() |> Zipper.down()
      :error -> zipper
    end
  end

  defp maybe_resolve_module_attribute(zipper), do: zipper

  defp maybe_resolve_block_to_last_child(%Zipper{node: {:__block__, _, _}} = zipper) do
    zipper
    |> Zipper.down()
    |> Zipper.rightmost()
    |> resolve_to_config()
  end

  defp maybe_resolve_block_to_last_child(zipper), do: zipper

  defp move_to_function_def(zipper, name, arity) do
    with :error <- Igniter.Code.Function.move_to_def(zipper, name, arity) do
      Igniter.Code.Function.move_to_defp(zipper, name, arity)
    end
  end

  defp ensure_key(zipper, key) do
    zipper = maybe_replace_nil_with_list(zipper)

    if Igniter.Code.List.list?(zipper) do
      case Igniter.Code.Keyword.set_keyword_key(zipper, key, nil) do
        {:ok, zipper} -> Igniter.Code.Keyword.get_key(zipper, key)
        :error -> :error
      end
    else
      :error
    end
  end

  defp maybe_replace_nil_with_list(%Zipper{node: nil} = zipper), do: Zipper.replace(zipper, [])
  defp maybe_replace_nil_with_list(zipper), do: zipper

  defp update_resolved(zipper, update_fun) do
    zipper_or_nil = if(is_nil(zipper.node), do: nil, else: zipper)

    case update_fun.(zipper_or_nil) do
      {:ok, nil} ->
        {:ok, zipper} = Common.move_upwards(zipper, &Common.node_matches_pattern?(&1, {_, _}))
        {:ok, Zipper.remove(zipper)}

      {:ok, {:code, quoted}} when is_binary(quoted) ->
        quoted = Sourceror.parse_string!(quoted)
        {:ok, Common.replace_code(zipper, quoted)}

      {:ok, {:code, quoted}} ->
        quoted =
          quoted
          |> Sourceror.to_string()
          |> Sourceror.parse_string!()

        {:ok, Common.replace_code(zipper, quoted)}

      other ->
        other
    end
  end

  defp ensure_path!(path) do
    non_empty? = Enum.count(path) <= 0
    all_atoms? = Enum.all?(path, &is_atom(&1))

    if non_empty? or not all_atoms? do
      raise ArgumentError, "path must be a non-empty list of atoms, got: #{inspect(path)}"
    end

    Enum.to_list(path)
  end
end
