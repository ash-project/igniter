defmodule Mix.Tasks.Igniter.Install.Spark do
  use Igniter.Mix.Task

  def igniter(igniter, _argv) do
    igniter
    |> Igniter.Formatter.add_formatter_plugin(Spark.Formatter)
    |> Igniter.Config.configure("config.exs", :spark, [:formatter, :remove_parens?], true, & &1)
  end
end
