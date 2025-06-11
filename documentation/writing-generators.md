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

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    [module_name | _] = igniter.args.argv

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
      updater: &Igniter.Code.List.prepend_new_to_list(&1, module_name)
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

## Task Groups

Igniter allows for _composing_ tasks, which means that many igniter tasks can be run in tandem. This happens automatically when using `mix igniter.install`, for example:
`mix igniter.install package1 package2`. You can also do this manually by using `Igniter.compose_task/3`. See the example above.

However, composing tasks means that sometimes a flag from one task may conflict with a flag from another task. Igniter will alert users when this happens, and ask them to
prefix the option with your task name. For example, the user may see an error like this:

```sh
Ambiguous flag provided `--option`.

The task or task groups `package1, package2` all define the flag `--option`.

To disambiguate, provide the arg as `--<prefix>.option`,
where `<prefix>` is the task or task group name.

For example:

`--package1.option`
```

It is not possible to prevent this from happening for all combinations of invocations of your task, but you can help by using a `group`.

```elixir
%Igniter.Mix.Task.Info{
  group: :your_package,
  ...
}
```

Setting this group performs two functions:

1. any tasks that share a group with each other will be assumed that the same flag has the same meaning. That way,
   users don't have to disambiguate when calling `mix igniter.install yourthing1 yourthing2 --option`, because it is assumed
   to have the same meaning.
2. it can provide a shorter/semantic name to type, i.e instead of `--ash-authentication-phoenix.install.domain` it could be just `--ash.domain`.

By default the group name is the _full task name_. We suggest setting a group for all of your tasks.
You should _not_ use a group name that is used by someone else, just like you should not use a module prefix used by someone else in general.

## Navigating the Igniter Codebase

A large part of writing generators with igniter is leveraging our built-in suite of tools for working with zippers and AST, as well as our off-the-shelf patchers for making project modifications. The codebase is split up into four primary divisions:

- `Igniter.Project.*` - project-level, off-the-shelf patchers
- `Igniter.Code.*` - working with zippers and manipulating source code
- `Igniter.Mix.*` - mix tasks, tools for writing igniter mix tasks
- `Igniter.Util.*` - various utilities and helpers
