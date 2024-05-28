defmodule Igniter.Formatter do
  alias Igniter.Common
  alias Sourceror.Zipper

  @default_formatter """
  # Used by "mix format"
  [
    inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
  ]
  """

  def import_dep(igniter, dep) do
    igniter
    |> Igniter.include_or_create_elixir_file(".formatter.exs", @default_formatter)
    |> Igniter.update_file(".formatter.exs", fn source ->
      quoted = Rewrite.Source.get(source, :quoted)
      zipper = Zipper.zip(quoted)

      new_code =
        zipper
        |> Zipper.down()
        |> case do
          nil ->
            code =
              quote do
                [import_deps: [unquote(dep)]]
              end

            zipper
            |> Igniter.Common.add_code(code)

          zipper ->
            zipper
            |> Zipper.rightmost()
            |> Common.put_in_keyword([:import_deps], [dep], fn nested_zipper ->
              Igniter.Common.prepend_new_to_list(
                nested_zipper,
                dep
              )
            end)
        end
        |> Zipper.root()

      Rewrite.Source.update(source, :import_formatter_dep, :quoted, new_code)
    end)
  end

  def add_formatter_plugin(igniter, plugin) do
    igniter
    |> Igniter.include_or_create_elixir_file(".formatter.exs", @default_formatter)
    |> Igniter.update_file(".formatter.exs", fn source ->
      quoted = Rewrite.Source.get(source, :quoted)
      zipper = Zipper.zip(quoted)

      new_code =
        zipper
        |> Zipper.down()
        |> case do
          nil ->
            code =
              quote do
                [plugins: [unquote(plugin)]]
              end

            zipper
            |> Igniter.Common.add_code(code)

          zipper ->
            zipper
            |> Zipper.rightmost()
            |> Common.put_in_keyword([:plugins], [Spark.Formatter], fn nested_zipper ->
              Igniter.Common.prepend_new_to_list(
                nested_zipper,
                Spark.Formatter,
                &Igniter.Common.equal_modules?/2
              )
            end)
        end
        |> Zipper.root()

      Rewrite.Source.update(source, :add_formatter_plugin, :quoted, new_code)
    end)
  end
end
