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
    source_folders: [
      type: {:list, :string},
      default: ["lib", "test/support"],
      doc: "A list of folders to manage elixir files in."
    ],
    dont_move_files: [
      type: {:list, :any},
      doc:
        "A list of strings or regexes. Any files that equal (in the case of strings) or match (in the case of regexes) will not be moved.",
      default: [
        ~r"lib/mix"
      ]
    ]
  ]

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
    igniter.assigns[:igniter_exs][config] || @configs[config][:default]
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
          Enum.reduce_while(@configs, {:ok, zipper}, fn {name, config}, {:ok, zipper} ->
            default =
              quote do
                unquote(config[:default])
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
