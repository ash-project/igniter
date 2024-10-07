defmodule Igniter.Test do
  @moduledoc "Tools for testing with igniter."

  @doc """
  Sets up a test igniter that has  only the files passed to it.

  ## Starting point

  All of the files of an empty mix project are added by default.
  You can specify more or overwrite the default files by passing a map of
  file paths to their contents.

  ## Limitations

  You cannot install new dependencies, or use dependencies your own project does not have.
  If you need to do that kind of thing, you will have to do a test that uses tools like
  `System.cmd` in a temporary directory.

  ## Options

  * `files` - A map of file paths to file contents. The file paths should be relative to the project root.
  * `app_name` - The name of the application. Defaults to `:test`.

  ## Examples

      test_project(files: %{
        "lib/foo.ex" => \"\"\"
        defmodule MyApp.Foo do
          use Ash.Resource
        end
        \"\"\"
      })
  """
  @spec test_project(opts :: Keyword.t()) :: Igniter.t()
  def test_project(opts \\ []) do
    Igniter.new()
    |> Igniter.assign(:test_mode?, true)
    |> Igniter.assign(:test_files, add_mix_new(opts))
    |> Igniter.Project.IgniterConfig.setup()
    |> apply_igniter!()
  end

  @doc """
  IO.puts the current igniter diff, and returns the igniter

  ## Options

  * `label` - A label to put before the diff.
  * `only` - File path(s) to only show the diff for
  """
  @spec puts_diff(Igniter.t(), opts :: Keyword.t()) :: Igniter.t()
  def puts_diff(igniter, opts \\ []) do
    igniter.rewrite.sources
    |> Map.values()
    |> then(fn sources ->
      if opts[:only] do
        Enum.filter(sources, &(&1.path in List.wrap(opts[:only])))
      else
        sources
      end
    end)
    |> Igniter.diff()
    |> String.trim()
    |> case do
      "" ->
        if opts[:label] do
          IO.puts("#{opts[:label]} No changes!")
        else
          IO.puts("No changes!")
        end

      diff ->
        if opts[:label] do
          IO.puts("#{opts[:label]}\n\n#{diff}")
        else
          IO.puts(diff)
        end
    end

    igniter
  end

  @doc """
  Applies an igniter, raising an error if there are any issues.

  See `apply_igniter/1` for more.
  """
  @spec apply_igniter!(Igniter.t()) :: Igniter.t() | no_return
  def apply_igniter!(igniter) do
    case apply_igniter(igniter) do
      {:ok, igniter, _} ->
        igniter

      {:error, error} ->
        raise "Error applying igniter:\n\n#{Enum.map_join(error, "\n", &"* #{&1}")}"
    end
  end

  @doc """
  Fakes applying the changes of an igniter.

  This function returns any tasks, errors, warnings.
  """
  @spec apply_igniter(Igniter.t()) ::
          {:ok, Igniter.t(),
           %{
             tasks: [{String.t(), list(String.t())}],
             warnings: [String.t()],
             notices: [String.t()]
           }}
          | {:error, [String.t()]}
  def apply_igniter(igniter) do
    case Igniter.prepare_for_write(igniter) do
      %{issues: []} = igniter ->
        new_igniter =
          igniter
          |> simulate_write()
          |> move_files()

        {:ok, new_igniter,
         %{tasks: igniter.tasks, warnings: igniter.warnings, notices: igniter.notices}}

      %{issues: issues} ->
        {:error, issues}
    end
  end

  defmacro assert_has_patch(igniter, path, patch) do
    quote bind_quoted: [igniter: igniter, path: path, patch: patch] do
      diff =
        igniter.rewrite.sources
        |> Map.take([path])
        |> Igniter.diff(color?: false)

      compare_diff =
        Igniter.Test.sanitize_diff(diff)

      compare_patch =
        Igniter.Test.sanitize_diff(patch, diff)

      compare_diff =
        if Igniter.Test.has_line_numbers?(compare_patch) do
          compare_diff
        else
          Igniter.Test.remove_line_numbers(compare_diff)
        end

      assert String.contains?(compare_diff, compare_patch),
             """
             Expected `#{path}` to contain the following patch:

             #{patch}

             Actual diff:

             #{diff}
             """

      igniter
    end
  end

  defmacro assert_unchanged(igniter, path_or_paths) do
    quote bind_quoted: [igniter: igniter, path_or_paths: path_or_paths] do
      for path <- List.wrap(path_or_paths) do
        refute Igniter.changed?(igniter, path), """
        Expected #{inspect(path)} to be unchanged, but it was changed.

        Diff:

        #{igniter.rewrite.sources |> Map.take([path]) |> Igniter.diff()}
        """
      end

      igniter
    end
  end

  defmacro assert_unchanged(igniter) do
    quote bind_quoted: [igniter: igniter] do
      refute Igniter.changed?(igniter), """
      Expected there to be no changes, but there were changes.

      Diff:

      #{Rewrite.sources(igniter.rewrite) |> Igniter.diff()}
      """

      igniter
    end
  end

  @doc false
  def has_line_numbers?(patch) do
    patch
    |> String.split("\n")
    |> Enum.any?(fn line ->
      case Integer.parse(String.trim(line)) do
        :error ->
          false

        _ ->
          true
      end
    end)
  end

  @doc false
  def remove_line_numbers(diff) do
    diff
    |> String.split("\n")
    |> Enum.map_join("\n", fn line ->
      String.replace(String.trim(line), ~r/^\d+/, "")
    end)
  end

  @doc false
  def sanitize_diff(diff, actual \\ nil) do
    diff
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "...|" || &1 == ""))
    |> Enum.flat_map(fn line ->
      if String.contains?(line, "|") do
        [line]
      else
        if actual do
          raise """
          Invalid patch provided.

          #{diff}

          Each line of the patch should contain at least one | character.

          Actual diff:

          #{actual}
          """
        else
          []
        end
      end
    end)
    |> Enum.map_join("\n", fn line ->
      [l, r] = String.split(line, "|", parts: 2)

      l =
        l
        |> String.split()
        |> Enum.join()

      String.trim(String.trim(l) <> String.trim(r))
    end)
  end

  defmacro assert_creates(igniter, path, content \\ nil) do
    quote bind_quoted: [igniter: igniter, path: path, content: content] do
      assert source = igniter.rewrite.sources[path],
             """
             Expected #{inspect(path)} to have been created, but it was not.
             #{Igniter.Test.created_files(igniter)}
             """

      assert source.from == :string,
             """
             Expected #{inspect(path)} to have been created, but it already existed.
             #{Igniter.Test.created_files(igniter)}
             """

      if content do
        actual_content = Rewrite.Source.get(source, :content)

        if actual_content != content do
          flunk("""
          Expected created file #{inspect(path)} to have the following contents:

          #{content}

          But it actually had the following contents:

          #{actual_content}

          Diff, showing your assertion against the actual contents:

          #{Rewrite.TextDiff.format(actual_content, content)}
          """)
        end
      end

      igniter
    end
  end

  @doc false
  def created_files(igniter) do
    igniter.rewrite
    |> Rewrite.sources()
    |> Enum.filter(&(&1.from == :string))
    |> Enum.map(& &1.path)
    |> case do
      [] ->
        "\nNo files were created."

      modules ->
        "\nThe following files were created:\n\n#{Enum.map_join(modules, "\n", &"* #{&1}")}"
    end
  end

  defp simulate_write(igniter) do
    igniter.rewrite
    |> Rewrite.sources()
    |> Enum.reduce(igniter.assigns[:test_files], fn source, test_files ->
      content = Rewrite.Source.get(source, :content)

      Map.put(test_files, source.path, content)
    end)
    |> then(fn test_files ->
      igniter
      |> Map.put(:rewrite, Rewrite.new())
      |> Map.put(:tasks, [])
      |> Map.put(:warnings, [])
      |> Map.put(:notices, [])
      |> Map.put(:issues, [])
      |> Map.put(:assigns, %{
        test_mode?: true,
        test_files: test_files,
        igniter_exs: igniter.assigns[:igniter_exs]
      })
    end)
  end

  defp move_files(igniter) do
    igniter.moves
    |> Enum.reduce(igniter.assigns[:test_files], fn {from, to}, files ->
      case Map.pop(files, from) do
        {nil, files} -> files
        {contents, files} -> Map.put(files, to, contents)
      end
    end)
    |> then(fn test_files ->
      igniter
      |> Igniter.assign(:test_files, test_files)
      |> Map.put(:moves, %{})
    end)
  end

  defp add_mix_new(opts) do
    app_name = opts[:app_name] || :test
    module_name = Module.concat([Macro.camelize(to_string(app_name))])

    opts[:files]
    |> Kernel.||(%{})
    |> Map.put_new("test/test_helper.exs", "ExUnit.start()")
    |> Map.put_new("test/#{app_name}_test.exs", """
    defmodule #{module_name}Test do
      use ExUnit.Case
      doctest #{module_name}

      test "greets the world" do
        assert #{module_name}.hello() == :world
      end
    end
    """)
    |> Map.put_new("lib/#{app_name}.ex", """
    defmodule #{module_name} do
      @moduledoc \"\"\"
      Documentation for `#{module_name}`.
      \"\"\"

      @doc \"\"\"
      Hello world.

      ## Examples

          iex> #{module_name}.hello()
          :world

      \"\"\"
      def hello do
        :world
      end
    end
    """)
    |> Map.put_new("README.md", """
      # #{module_name}

      **TODO: Add description**

      ## Installation

      If [available in Hex](https://hex.pm/docs/publish), the package can be installed
      by adding `thing` to your list of dependencies in `mix.exs`:

      ```elixir
      def deps do
        [
          {:#{app_name}, "~> 0.1.0"}
        ]
      end
      ```

      Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
      and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
      be found at <https://hexdocs.pm/#{app_name}>.
    """)
    |> Map.put_new(".formatter.exs", """
    # Used by "mix format"
    [
      inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
    ]
    """)
    |> Map.put_new(".gitignore", """
    # The directory Mix will write compiled artifacts to.
    /_build/

    # If you run "mix test --cover", coverage assets end up here.
    /cover/

    # The directory Mix downloads your dependencies sources to.
    /deps/

    # Where third-party dependencies like ExDoc output generated docs.
    /doc/

    # Ignore .fetch files in case you like to edit your project deps locally.
    /.fetch

    # If the VM crashes, it generates a dump, let's ignore it too.
    erl_crash.dump

    # Also ignore archive artifacts (built via "mix archive.build").
    *.ez

    # Ignore package tarball (built via "mix hex.build").
    #{app_name}-*.tar

    # Temporary files, for example, from tests.
    /tmp/
    """)
    |> Map.put_new("mix.exs", """
    defmodule #{module_name}.MixProject do
      use Mix.Project

      def project do
        [
          app: :#{app_name},
          version: "0.1.0",
          elixir: "~> 1.17",
          start_permanent: Mix.env() == :prod,
          deps: deps()
        ]
      end

      # Run "mix help compile.app" to learn about applications.
      def application do
        [
          extra_applications: [:logger]
        ]
      end

      # Run "mix help deps" to learn about dependencies.
      defp deps do
        [
          # {:dep_from_hexpm, "~> 0.3.0"},
          # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
        ]
      end
    end
    """)
  end
end
