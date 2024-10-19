defmodule Mix.Tasks.Igniter.AddExtension do
  use Igniter.Mix.Task

  @example "mix igniter.add_extension phoenix"

  @shortdoc "Adds an extension to your `.igniter.exs` configuration file."
  @moduledoc """
  #{@shortdoc}

  The extension can be the module name of an extension,
  or the string `phoenix`, which maps to `Igniter.Extensions.Phoenix`.

  ## Example

  ```bash
  #{@example}
  ```

  """

  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :igniter,
      example: @example,
      positional: [:extension]
    }
  end

  def igniter(igniter, argv) do
    {%{extension: extension}, _argv} = positional_args!(argv)

    extension =
      if extension == "phoenix" do
        Igniter.Extensions.Phoenix
      else
        Igniter.Project.Module.parse(extension)
      end

    igniter
    |> Igniter.Project.IgniterConfig.add_extension(extension)
  end
end
