![Logo](https://github.com/ash-project/igniter/blob/main/logos/igniter-logo-small.png?raw=true#gh-light-mode-only)
![Logo](https://github.com/ash-project/igniter/blob/main/logos/igniter-logo-small.png?raw=true#gh-dark-mode-only)

![Elixir CI](https://github.com/ash-project/igniter/workflows/Ash%20CI/badge.svg)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Hex version badge](https://img.shields.io/hexpm/v/igniter.svg)](https://hex.pm/packages/igniterh)
[![Hexdocs badge](https://img.shields.io/badge/docs-hexdocs-purple)](https://hexdocs.pm/igniter)

# Igniter

Igniter is a code generation and project patching framework.

## Installation

Igniter can be added to an existing elixir project by adding it to your dependencies:

```elixir
{:igniter, "~> 0.1", only: [:dev]}
```

You can also generate new projects with igniter preinstalled, and run installers in the same command.

The archive is not published yet, so these instructions are ommitted, but once it is, you will be able to install the archive, and say:

```
mix igniter.new app_name --install ash
```

## Patterns

Mix tasks built with igniter are both individually callable, _and_ composable. This means that tasks can call eachother, and also end users can create and customize their own generators composing existing tasks.

### Installers

Igniter will look for a task called `<your_package>.install` when the user runs `mix igniter.install <your_package>`, and will run it after installing and fetching dependencies.

### Generators/Patchers

These can be run like any other mix task, or composed together. For example, lets say that you wanted to have your own `Ash.Resource` generator, that starts with the default `mix ash.gen.resource` task, but then adds or modifies files:

```elixir
# in lib/mix/tasks/my_app.gen.resource.ex
defmodule Mix.Tasks.MyApp.Gen.Resource do
  use Igniter.Mix.Task

  def igniter(igniter, [resource | _] = argv) do
    resource = Igniter.Code.Module.parse(resource)
    my_special_thing = Module.concat([resource, SpecialThing])
    location = Igniter.Code.Module.proper_location(my_special_thing)

    igniter
    |> Igniter.compose_task("ash.gen.resource", argv)
    |> Igniter.create_new_elixir_file(location, """
    defmodule #{inspect(my_special_thing)} do
      # this is the special thing for #{inspect()}
    end
    """)
  end
end
```
