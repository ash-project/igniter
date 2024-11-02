defmodule Mix.Tasks.Igniter.InstallPhoenix do
  use Igniter.Mix.Task

  @example "mix igniter.install_phoenix"
  @shortdoc "Install Phoenix project files"

  @moduledoc """
  #{@shortdoc}

  ## Example

  ```bash
  #{@example}
  ```

  ## Options

  # TODO: phx.new options (--umbrella, --no-ecto, etc)
  # https://github.com/phoenixframework/phoenix/blob/7586cbee9e37afbe0b3cdbd560b9e6aa60d32bf6/installer/lib/mix/tasks/phx.new.ex#L13
  """

  def info(_argv, _source) do
    %Igniter.Mix.Task.Info{
      group: :igniter,
      example: @example,
      positional: [:base_path]
    }
  end

  def igniter(igniter, argv) do
    # TODO: check elixir version - https://github.com/phoenixframework/phoenix/blob/7586cbee9e37afbe0b3cdbd560b9e6aa60d32bf6/installer/lib/mix/tasks/phx.new.ex#L380

    {%{base_path: base_path}, argv} = positional_args!(argv)
    _options = options!(argv)

    # TODO: umbrella
    generate(igniter, base_path, {Phx.New.Single, Igniter.Phoenix.Single}, :base_path)
  end

  # TODO: opts
  # TODO: call validate_project(path)
  # TODO: perform some of the validations - https://github.com/phoenixframework/phoenix/blob/7586cbee9e37afbe0b3cdbd560b9e6aa60d32bf6/installer/lib/mix/tasks/phx.new.ex#L187
  defp generate(igniter, base_path, {phx_generator, igniter_generator}, _path, opts \\ []) do
    project =
      base_path
      |> Phx.New.Project.new(opts)
      |> phx_generator.prepare_project()
      |> Phx.New.Generator.put_binding()

    igniter_generator.generate(igniter, project)
  end
end
