defmodule Mix.Tasks.Igniter.Install do
  @moduledoc """
  Install a package or packages, and run any associated installers.

  ## Args

  mix igniter.install package1 package2 package3

  ## Package formats

  * `package` - The latest version of the package will be installed, pinned at the
     major version, or minor version if there is no major version yet.
  * `package@version` - The package will be installed at the specified version.
     If the version given is generic, like `3.0`, it will be pinned as described above.
     if it is specific, like `3.0.1`, it will be pinned at that *exact* version with `==`.
  * `package@git:git_url` - The package will be installed from the specified git url.
  * `package@github:project/repo` - The package will be installed from the specified github repo.
  * `package@path:path/to/dep` - The package will be installed from the specified path.

  Additionally, a Git ref can be specified when using `git` or `github`:

  * `package@git:git_url@ref`

  ## Switches

  * `--dry-run` - Run the task without making any changes.
  * `--yes` - Automatically answer yes to any prompts.
  * `--yes-to-deps` - Automatically answer yes to any prompts about installing new deps.
  * `--verbose` - Display additional output from various operations.
  * `--example` - Request that installed packages include initial example code.
  """

  use Mix.Task

  @impl true
  @shortdoc "Install a package or packages, and run any associated installers."
  def run(argv) do
    Igniter.Util.Loading.with_spinner(
      "compile",
      fn ->
        Mix.Task.run("deps.compile")
        Mix.Task.run("deps.loadpaths")
        Mix.Task.run("compile", ["--no-compile"])
      end,
      verbose?: "--verbose" in argv
    )

    {argv, positional} = extract_positional_args(argv)

    packages =
      positional
      |> Enum.join(",")
      |> String.split(",", trim: true)

    if Enum.empty?(packages) do
      raise ArgumentError, "must provide at least one package to install"
    end

    Application.ensure_all_started(:rewrite)

    Igniter.Util.Install.install(Enum.join(packages, ","), argv)
  end

  @doc false
  defp extract_positional_args(argv) do
    do_extract_positional_args(argv, [], [])
  end

  defp do_extract_positional_args([], argv, positional), do: {argv, positional}

  defp do_extract_positional_args(argv, got_argv, positional) do
    case OptionParser.next(argv, switches: []) do
      {_, _key, true, rest} ->
        do_extract_positional_args(
          rest,
          got_argv ++ [Enum.at(argv, 0)],
          positional
        )

      {_, _key, _value, rest} ->
        count_consumed = Enum.count(argv) - Enum.count(rest)

        do_extract_positional_args(
          rest,
          got_argv ++ Enum.take(argv, count_consumed),
          positional
        )

      {:error, rest} ->
        [first | rest] = rest
        do_extract_positional_args(rest, got_argv, positional ++ [first])
    end
  end
end
