<!--
SPDX-FileCopyrightText: 2020 Zach Daniel
SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs.contributors>

SPDX-License-Identifier: MIT
-->

# Documenting Tasks

Igniter.Scribe is a powerful tool that allows you to automatically generate documentation for your installers and mix tasks. Instead of writing static documentation that can quickly become outdated, you can create living documentation that shows exactly what your tasks do by running them in a test environment.

## Overview

The `--scribe` option available on all Igniter mix tasks enables automatic documentation generation. When you run a task with this option, Igniter will:

1. Set up a test project environment
2. Execute your task's logic
3. Capture all the changes made to files
4. Generate a markdown document showing the step-by-step process
5. Save the documentation to the specified file path

## Basic Usage

To generate documentation for any Igniter mix task, use the `--scribe` option followed by the output file path:

```bash
mix your.task --scribe documentation/tutorials/your-guide.md
```

## Setting Up Your Task for Scribe

```elixir
defmodule Mix.Tasks.YourLibrary.Install do
  @shortdoc "Installs YourLibrary into a project"

  @moduledoc """
  #{@shortdoc}

  ## Options

  - `--example` - Creates example resources
  """

  use Igniter.Mix.Task

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    igniter
    |> Igniter.Scribe.start_document(
      "Manual Installation Guide",
      @manual_lead_in,
      app_name: :my_app
    )
    |> add_your_sections()
  end
end
```

## Scribe API Reference

### `start_document/4`

Initializes the documentation with a title and introduction. Only the first call to this function is honored.

```elixir
Igniter.Scribe.start_document(igniter, title, contents, opts \\ [])
```

**Parameters:**
- `igniter` - The Igniter struct
- `title` - The main title for the document (will be rendered as `# Title`)
- `contents` - Introduction text that appears after the title
- `opts` - Optional keyword list (can include `:app_name` and other options)

**Example:**

```elixir
@manual_lead_in """
This guide will walk you through the process of manually installing YourLibrary into your project.
If you are starting from scratch, you can use `mix new` or `mix igniter.new` and follow these instructions.
"""

igniter
|> Igniter.Scribe.start_document(
  "Manual Installation",
  @manual_lead_in,
  app_name: :my_app
)
```

### `section/3`

Creates a new section in the documentation with a header, explanation, and the actual changes.

```elixir
Igniter.Scribe.section(igniter, header, explanation, callback)
```

**Parameters:**
- `igniter` - The Igniter struct
- `header` - The section header text
- `explanation` - Descriptive text explaining what this section does
- `callback` - A function that receives the igniter and performs the actual changes

**Example:**

```elixir
@setup_dependencies """
Install and configure the required dependencies for YourLibrary.
This will add the necessary packages to your mix.exs file.
"""

igniter
|> Igniter.Scribe.section("Setup Dependencies", @setup_dependencies, fn igniter ->
  igniter
  |> Igniter.Scribe.patch(&Igniter.Project.Deps.add_dep(&1, {:other_library, "~> 1.0"}))
  |> Igniter.Scribe.patch(&Igniter.compose_task(&1, "other_library.install"))
end)
```

### `patch/2`

Captures changes made by a function and includes them in the documentation as code diffs.

```elixir
Igniter.Scribe.patch(igniter, callback)
```

**Parameters:**
- `igniter` - The Igniter struct
- `callback` - A function that receives the igniter and returns a modified igniter

The patch function will:
- Compare the before and after state of files
- Generate diffs for modified files
- Show creation of new files with full content
- Automatically format the output with appropriate syntax highlighting

**Example:**

```elixir
igniter
|> Igniter.Scribe.patch(fn igniter ->
  igniter
  |> Igniter.Project.Config.configure("config.exs", :your_library, [:option], true)
  |> Igniter.Project.Module.create_module(YourApp.SomeModule, """
  defmodule YourApp.SomeModule do
    # Module content here
  end
  """)
end)
```

## Best Practices

### 1. Use Descriptive Section Names and Explanations

Choose clear, descriptive names for your sections and provide helpful explanations:

```elixir
@setup_formatter """
Configure the DSL auto-formatter. This tells the formatter to remove excess parentheses
and how to sort sections in your modules for consistency.
"""

igniter
|> Igniter.Scribe.section("Setup The Formatter", @setup_formatter, fn igniter ->
  # Implementation
end)
```

### 2. Group Related Changes

Group logically related changes together within sections:

```elixir
igniter
|> Igniter.Scribe.section("Configure Application", @config_explanation, fn igniter ->
  igniter
  |> Igniter.Scribe.patch(&configure_main_settings/1)
  |> Igniter.Scribe.patch(&configure_optional_settings/1)
  |> Igniter.Scribe.patch(&setup_environment_configs/1)
end)
```

### 3. Use Module Attributes for Documentation

Store your documentation strings in module attributes to keep them organized and reusable:

```elixir
defmodule Mix.Tasks.YourLibrary.Install do
  @manual_lead_in """
  This guide walks you through manually installing YourLibrary.
  """

  @dependency_setup """
  Install required dependencies and configure them for your project.
  """

  @formatter_setup """
  Configure code formatting for your DSL.
  """

  # Use these throughout your igniter/1 function
end
```

## Example: Complete Installer

Take a look at Ash Framework's installer [here](https://github.com/ash-project/ash/blob/main/lib/mix/tasks/install/ash.install.ex), and see the generated markdown file [here](https://github.com/ash-project/ash/blob/main/documentation/topics/advanced/pagination.livemd).
