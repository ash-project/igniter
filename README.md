<!--
SPDX-FileCopyrightText: 2020 Zach Daniel
SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs.contributors>

SPDX-License-Identifier: MIT
-->

<img src="https://github.com/ash-project/igniter/blob/main/logos/igniter-logo-small.png?raw=true#gh-light-mode-only" alt="Logo Light" width="250">
<img src="https://github.com/ash-project/igniter/blob/main/logos/igniter-logo-small.png?raw=true#gh-dark-mode-only" alt="Logo Dark" width="250">

[![CI](https://github.com/ash-project/igniter/actions/workflows/elixir.yml/badge.svg)](https://github.com/ash-project/igniter/actions/workflows/elixir.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Hex version badge](https://img.shields.io/hexpm/v/igniter.svg)](https://hex.pm/packages/igniter)
[![Hexdocs badge](https://img.shields.io/badge/docs-hexdocs-purple)](https://hexdocs.pm/igniter)
[![REUSE status](https://api.reuse.software/badge/github.com/ash-project/igniter)](https://api.reuse.software/info/github.com/ash-project/igniter)

# Igniter

Igniter is a code generation and project patching framework.

There are two audiences for Igniter:
- **End-users**:
  - Provides tasks like `mix igniter.install` to automatically add dependencies to your project
  - Provides upgraders to upgrade your deps and apply codemods at the same time
  - Provides refactors like `mix igniter.refactor.rename_function` to refactor your code automatically
- **Library authors and platform teams**: Igniter is a toolkit for writing smarter generators that can semantically create _and modify_ existing files in end-user's projects (e.g. codemods)

## For end-users

### Installers

Igniter provides `mix igniter.install`, which will automatically _add the dependency to your mix.exs_ and then run
that library's installer if it has one.

### Upgraders

The `mix igniter.upgrade` mix task is a drop-in replacement for `mix deps.update` but it will additionally
run any upgrade patchers defined in the target package (if there are any).

See the [upgrades guide](/documentation/upgrades.md) guide for more.

### Refactors

In addition to providing tools for library authors to patch your code, common operations are available to use as needed.

- `mix igniter.refactor.rename_function` - Rename a function in your application, along with all references to it. Optionally it can also mark the previous function as deprecated.

### Others

- `mix igniter.update_gettext` - Use this to update [gettext](https://github.com/elixir-gettext/gettext) if your version of gettext is lower than 0.26.1 and you are seeing a compile warning
  about gettext backends.


### Installation

Igniter requires Elixir 1.15+, but 1.17+ is recommended for full compatibility.

#### Standard Installation for end-users

Add Igniter to an existing elixir project by adding it to your dependencies in `mix.exs`:

```elixir
{:igniter, "~> 0.6", only: [:dev, :test]}
```

Note: If you only want to use `mix igniter.install` to add dependencies to your project then you can install the archive instead of adding Igniter to your project.

#### Installing globally via an archive

First, install the archive:

```elixir
mix archive.install hex igniter_new
```

Then you can run `mix igniter.new` to generate a new elixir project

```
mix igniter.new app_name --install ash
```

### Creating a new mix project using Igniter

If you want to create a new mix project that uses ash and ecto you can run a command like:

```
mix igniter.new app_name --install ash,ecto
```

You can also combine an Igniter install command with existing project generators (e.g. `mix phx.new`) by specifying the mix task name with the `--with` flag. If you want to pass arguments to the existing project generator/task you can pass them with `--with-args`:

```
mix igniter.new app_name --install ash --with phx.new --with-args="--no-ecto --no-html"
```

## For library authors and platform teams

Igniter is a toolkit for writing smarter generators that can semantically create _and modify_ existing files.

### Installing for library authors

For library authors, add Igniter to your `mix.exs` with `optional: true`:

```elixir
{:igniter, "~> 0.6", optional: true}
```

`optional: true` ensures that end users can install as outlined above, and `:igniter` will not be included in their production application.

### Patterns

Mix tasks built with Igniter are both individually callable, _and_ composable. This means that tasks can call each other, and also end-users can create and customize their own generators composing existing tasks.

### Installers

Igniter will look for a task called `<your_package>.install` when the user runs `mix igniter.install <your_package>`, and will run it after installing and fetching dependencies.

To create your installer, use `mix igniter.gen.task <your_package>.install`

### Generators/Patchers

Generators created with Igniter can be run like any other mix task, or composed together. For example, lets say that you wanted to have your own `Ash.Resource` generator, that starts with the default `mix ash.gen.resource` task, but then adds or modifies additional files:

To create your generator, use `mix igniter.gen.task <your_package>.task.name`

```elixir
# in lib/mix/tasks/my_app.gen.resource.ex
defmodule Mix.Tasks.MyApp.Gen.Resource do
  use Igniter.Mix.Task

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    [resource | _] = igniter.args.argv

    resource = Igniter.Code.Module.parse(resource)
    my_special_thing = Module.concat([resource, SpecialThing])
    location = Igniter.Code.Module.proper_location(my_special_thing)

    igniter
    |> Igniter.compose_task("ash.gen.resource", igniter.args.argv)
    |> Igniter.Project.Module.create_module(my_special_thing, """
      # this is the special thing for #{inspect()}
    """)
  end
end
```

## Upgrading to 0.4.x

You may notice an issue running `mix igniter.upgrade` if you are using `0.3.x` versions.
you must manually upgrade Igniter (by editing your `mix.exs` file or running `mix deps.update`)
to a version greater than or equal to `0.3.78` before running `mix igniter.upgrade`. A problem
was discovered with the process of Igniter upgrading itself or one of its dependencies.

In any case where Igniter must both download and compile a new version of itself, it will exit
and print instructions with a command you can run to complete the upgrade. For example:

`mix igniter.apply_upgrades igniter:0.4.0:0.5.0 package:0.1.3:0.1.4`
