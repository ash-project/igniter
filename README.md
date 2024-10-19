<img src="https://github.com/ash-project/igniter/blob/main/logos/igniter-logo-small.png?raw=true#gh-light-mode-only" alt="Logo Light" width="250">
<img src="https://github.com/ash-project/igniter/blob/main/logos/igniter-logo-small.png?raw=true#gh-dark-mode-only" alt="Logo Dark" width="250">

[![CI](https://github.com/ash-project/igniter/actions/workflows/elixir.yml/badge.svg)](https://github.com/ash-project/igniter/actions/workflows/elixir.yml)
[![Hex version badge](https://img.shields.io/hexpm/v/igniter.svg)](https://hex.pm/packages/igniter)
[![Hexdocs badge](https://img.shields.io/badge/docs-hexdocs-purple)](https://hexdocs.pm/igniter)

# Igniter

Igniter is a code generation and project patching framework.

## For library authors and platform teams

This is a tool kit for writing smarter generators that can semantically create and modify existing files.

## For end-users

### Installers

You can install new dependencies `mix igniter.install`, which will _add it to your mix.exs automatically_ and then run
that library's installer if it has one. Even when libraries don't have an installer, or use igniter, this behavior
makes it useful to keep around.

### Upgraders

You can upgrade dependencies with `mix igniter.upgrade`, as a drop on replacement for `mix deps.update`. This
will update your dependencies and run any upgrade patchers defined in the target package (if there are any).

See [upgrades guide](/documentation/upgrades.md) guide for more.

### Refactors

In addition to providing tools for library authors to patch your code, common operations are available to use as needed.

- `mix igniter.refactor.rename_function` - Use this to rename a function in your application, along with all references to it.

### Others

- `mix igniter.update_gettext` - Use this to update gettext if your version is lower than 0.26.1 and you are seeing a compile warning
  about gettext backends.

## Installation

Igniter can be added to an existing elixir project by adding it to your dependencies:

```elixir
{:igniter, "~> 0.1"}
```

You can also generate new projects with igniter preinstalled, and run installers in the same command.

First, install the archive:

```elixir
mix archive.install hex igniter_new
```

Then you can run `mix igniter.new`

```
mix igniter.new app_name --install ash
```

Or if you want to use a different project creator, specify the mix task name with the `--with` flag. Any arguments will be passed through to that task, with the exception of `--install` and `--example`.

```
mix igniter.new app_name --install ash --with phx.new --no-ecto
```

## Patterns

Mix tasks built with igniter are both individually callable, _and_ composable. This means that tasks can call each other, and also end users can create and customize their own generators composing existing tasks.

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
