# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule Igniter.Project.IgniterConfig do
  @configs [
    module_location: [
      type: {:in, [:outside_matching_folder, :inside_matching_folder]},
      default: :outside_matching_folder,
      doc: """
        - `:outside_matching_folder`, modules will be placed in a folder exactly matching their path.
        - `:inside_matching_folder`, modules who's name matches an existing folder will be placed inside that folder,
          or moved there if the folder is created.
      """
    ],
    extensions: [
      type:
        {:list,
         {:or,
          [
            {:behaviour, Igniter.Extension},
            {:tuple, [{:behaviour, Igniter.Extension}, :keyword_list]}
          ]}},
      default: [],
      doc: "A list of extensions to use in the project."
    ],
    deps_location: [
      type: {:or, [:last_list_literal, {:tagged_tuple, :variable, :atom}, :mfa]},
      default: :last_list_literal,
      doc: """
      The strategy for finding the `deps` list to add new dependencies to, in your `deps/0` function in `mix.exs`

        - `:last_list_literal` expects your deps function to return a literal list which will be prepended to
        - `{:variable, :name}` expects to find an assignment from the given variable to a list literal, i.e `deps = [...]`, and prepends to that
        - `:mfa` will call the given mfa with the igniter and the zipper within the `deps/0` function. It should return `{:ok, zipper}`
           at the position where the dep should be prepended, or :error if the location could not be found.
      """
    ],
    source_folders: [
      type: {:list, :string},
      default: ["lib", "test/support"],
      doc: "A list of folders to manage elixir files in."
    ],
    dont_move_files: [
      type: {:list, :any},
      doc:
        "A list of strings or regexes. Any files that equal (in the case of strings) or match (in the case of regexes) will not be moved."
    ]
  ]

  def configs do
    Keyword.update(@configs, :dont_move_files, [], fn options ->
      # We use this trick to inject values that cannot be stored in a module constant as of Erlang/OTP 28
      Keyword.merge(options,
        default: [
          ~r"lib/mix"
        ],
        quoted_default:
          quote do
            [~r"lib/mix"]
          end
      )
    end)
  end

  docs =
    Enum.map_join(@configs, "\n", fn {name, config} ->
      "- `#{name}` - \n#{config[:doc]}"
    end)

  @moduledoc """
  Tools for reading and modifying the `.igniter.exs` file.

  The command `mix igniter.setup` will generate this file, as well
  as keep it up to date with any new configurations. You can run this
  command at any time to update the file without overriding your own config.

  If the file does not exist, all values are considered to have their default value.

  ## Options

  #{docs}
  """

  def get(igniter, config) do
    igniter.assigns[:igniter_exs][config] || configs()[config][:default]
  end

  def add_extension(igniter, extension) do
    extension =
      case extension do
        {mod, opts} -> {mod, opts}
        mod -> {mod, []}
      end

    quoted =
      extension
      |> Macro.escape()
      |> Sourceror.to_string()
      |> Sourceror.parse_string!()

    igniter
    |> setup()
    |> Igniter.update_elixir_file(".igniter.exs", fn zipper ->
      rightmost = Igniter.Code.Common.rightmost(zipper)

      if Igniter.Code.List.list?(rightmost) do
        Igniter.Code.Keyword.set_keyword_key(
          zipper,
          :extensions,
          [quoted],
          fn zipper ->
            case Igniter.Code.List.move_to_list_item(zipper, fn zipper ->
                   if Igniter.Code.Tuple.tuple?(zipper) do
                     with {:ok, item} <- Igniter.Code.Tuple.tuple_elem(zipper, 0),
                          true <- Igniter.Code.Common.nodes_equal?(item, elem(extension, 0)) do
                       true
                     else
                       _ ->
                         false
                     end
                   else
                     Igniter.Code.Common.nodes_equal?(zipper, elem(extension, 0))
                   end
                 end) do
              {:ok, _} ->
                {:ok, zipper}

              _ ->
                Igniter.Code.List.prepend_to_list(zipper, quoted)
            end
          end
        )
      else
        {:warning,
         "Failed to modify `.igniter.exs` when adding the extension #{inspect(extension)} because its last return value is not a list literal."}
      end
    end)
  end

  def configure(igniter, key, value) do
    value =
      value
      |> Macro.escape()
      |> Sourceror.to_string()
      |> Sourceror.parse_string!()

    igniter
    |> setup()
    |> Igniter.update_elixir_file(".igniter.exs", fn zipper ->
      rightmost = Igniter.Code.Common.rightmost(zipper)

      if Igniter.Code.List.list?(rightmost) do
        Igniter.Code.Keyword.set_keyword_key(
          zipper,
          key,
          [value],
          fn zipper ->
            {:ok, Igniter.Code.Common.replace_code(zipper, value)}
          end
        )
      else
        {:warning, "Failed to modify `.igniter.exs` when configuring #{inspect(key)}"}
      end
    end)
  end

  def dont_move_file_pattern(igniter, pattern) do
    quoted =
      case pattern do
        %Regex{} = pattern ->
          Sourceror.parse_string!(inspect(pattern))

        pattern ->
          pattern
          |> Macro.escape()
          |> Sourceror.to_string()
          |> Sourceror.parse_string!()
      end

    igniter
    |> setup()
    |> Igniter.update_elixir_file(".igniter.exs", fn zipper ->
      rightmost = Igniter.Code.Common.rightmost(zipper)

      if Igniter.Code.List.list?(rightmost) do
        Igniter.Code.Keyword.set_keyword_key(
          zipper,
          :dont_move_files,
          [quoted],
          fn zipper ->
            Igniter.Code.List.prepend_new_to_list(zipper, quoted)
          end
        )
      else
        {:warning,
         "Failed to modify `.igniter.exs` when adding the ignore module pattern #{inspect(pattern)} because its last return value is not a list literal."}
      end
    end)
  end

  def setup(igniter) do
    Igniter.create_or_update_elixir_file(
      igniter,
      ".igniter.exs",
      """
      # This is a configuration file for igniter.
      # For option documentation, see https://hexdocs.pm/igniter/Igniter.Project.IgniterConfig.html
      # To keep it up to date, use `mix igniter.setup`

      []
      """,
      &{:ok, &1}
    )
    |> Igniter.update_elixir_file(
      ".igniter.exs",
      fn zipper ->
        rightmost = Igniter.Code.Common.rightmost(zipper)

        if Igniter.Code.List.list?(rightmost) do
          Enum.reduce_while(configs(), {:ok, zipper}, fn {name, config}, {:ok, zipper} ->
            default =
              config[:quoted_default] ||
                quote do
                  unquote(Macro.escape(config[:default]))
                end

            set_result =
              Igniter.Code.Common.within(zipper, fn zipper ->
                Igniter.Code.Keyword.set_keyword_key(
                  zipper,
                  name,
                  default,
                  fn zipper ->
                    {:ok, zipper}
                  end
                )
              end)

            # when we have a way to comment ahead of a keyword item
            # we should comment the docs
            case set_result do
              {:ok, zipper} ->
                {:cont, {:ok, zipper}}

              :error ->
                {:halt,
                 {:warning,
                  "Failed to modify `.igniter.exs` while trying to set default value for #{name}: #{inspect(default)}"}}
            end
          end)
        else
          {:warning,
           "Failed to modify `.igniter.exs` because its last return value is not a list literal"}
        end
      end
    )
  end
end
