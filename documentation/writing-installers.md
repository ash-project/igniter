# Writing Installers

Generate the install task:
```
mix igniter.gen.task my_dep.install
```
All of the work will be done in the igniter call:

```elixir
@impl Igniter.Mix.Task
def igniter(igniter) do
  # Do your work here and return an updated igniter
  igniter
  |> Igniter.add_warning("mix routex.install is not yet implemented")
end
```

## Fetching Dependency

```elixir
if Igniter.Project.Deps.has_dep?(igniter, :my_dep) do
  igniter
else
  igniter
  |> Igniter.Project.Deps.add_dep({:my_dep, "~> 1.0"})
  |> Igniter.apply_and_fetch_dependencies(error_on_abort?: true, yes_to_deps: true)
end
```

Check does the dependency already exist and if not add it and apply it.


## Creating a module

```elixir
Igniter.Project.Module.create_module(igniter, module, """
use MyDep.Module
""")
```

Create a new module that uses some module from your application.

## Modifying a module

For example:

```elixir
defmodule SomeModule do
  alias Some.Example

  def some_function(a, b) do
    Example.function(a, b)
  end
end
```

Find that module and update it:

```elixir
Igniter.Project.Module.find_and_update_module!(igniter, SomeModule, fn zipper ->
  {:ok, igniter}
end)
```

In the function block use [`within/2`](https://hexdocs.pm/igniter/Igniter.Code.Common.html#within/2) to do multiple modifications. Find the part you want to change and modify it.

For example:
 - replace alias with an import:
```elixir
Igniter.Code.Common.within(fn zipper ->
  pred = &match?(%Zipper{node: {:alias, _, _}}, &1)
  zipper = Common.remove(zipper, pred)
  line = "import Some.Example, only: [:function]"
  {:ok, Common.add_code(zipper, line, placement: :before)}
end)
```

 - replace function block:
 ```elixir
Igniter.Code.Common.within(fn zipper ->
  {:ok, zipper} = move_to_function(zipper, :some_function)
  {:ok, zipper} = Common.move_to_do_block(zipper)
  line = "my_private_function!(function(a, b))"
  {:ok, Igniter.Code.Common.replace_code(zipper, line)}
end)
```

 - add a block:
 ```elixir
Igniter.Code.Common.within(fn zipper ->
  block = """
  defp private_function!({:ok, result}), do: result
  defp private_function!(_), do: raise "Something went wrong!"
  """

  {:ok, Common.add_code(zipper, block, placement: :after)}
end)
```

You can chain within blocks using `with`.