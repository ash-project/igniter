# Writing Generators

In `Igniter`, generators are done as a wrapper around `Mix.Task`, allowing them to be called individually or composed as part of a task.

Since an example is worth a thousand words, lets take a look at an example that generates a file and ensures a configuration is set in the user's `config.exs`.

> ### An igniter for igniters?! {: .info}
>
> Run `mix igniter.gen.task your_app.task.name` to generate a new, fully configured igniter task!

```elixir
# lib/mix/tasks/your_lib.gen.your_thing.ex
defmodule Mix.Tasks.YourLib.Gen.YourThing do
  use Igniter.Mix.Task

  def igniter(igniter, [module_name | _ ] = argv) do
    module_name = Igniter.Code.Module.parse(module_name)
    path = Igniter.Code.Module.proper_location(module_name)
    app_name = Igniter.Project.Application.app_name(igniter)

    igniter
    |> Igniter.create_new_elixir_file(path, """
    defmodule #{inspect(module_name)} do
      use YourLib.Thing

      ...some_code
    end
    """)
    |> Igniter.Project.Config.configure(
      "config.exs",
      app_name,
      [:list_of_things],
      [module_name],
      &Igniter.Code.List.prepend_new_to_list(&1, module_name)
    )
  end
end
```

Now, your users can run

`mix your_lib.gen.your_thing MyApp.MyModuleName`

and it will present them with a diff, creating a new file and updating their `config.exs`.

Additionally, other generators can "compose" this generator using `Igniter.compose_task/3`

```elixir
igniter
|> Igniter.compose_task(Mix.Tasks.YourLib.Gen.YourThing, ["MyApp.MyModuleName"])
|> Igniter.compose_task(Mix.Tasks.YourLib.Gen.YourThing, ["MyApp.SomeOtherName"])
```

## Writing a library installer

Igniter will look for a mix task called `your_library.install` when a user runs `mix igniter.install your_library`. As long as it has the correct name, it will be run automatically as part of installation!

## Navigating the Igniter Codebase

A large part of writing generators with igniter is leveraging our built-in suite of tools for working with zippers and AST, as well as our off-the-shelf patchers for making project modifications. The codebase is split up into four primary divisions:

- `Igniter.Project.*` - project-level, off-the-shelf patchers
- `Igniter.Code.*` - working with zippers and manipulating source code
- `Igniter.Mix.*` - mix tasks, tools for writing igniter mix tasks
- `Igniter.Util.*` - various utilities and helpers
