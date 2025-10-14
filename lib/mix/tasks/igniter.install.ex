# SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs.contributors>
#
# SPDX-License-Identifier: MIT

ignore_module_conflict = Code.get_compiler_option(:ignore_module_conflict)

Code.put_compiler_option(:ignore_module_conflict, true)

defmodule Mix.Tasks.Igniter.Install do
  @moduledoc """
  Install a package or packages, running any Igniter installers.

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
  * `package@github:project/repo@ref` - The package will be installed from the specified github repo, at the specified ref (i.e tag, branch, commit).
  * `package@path:path/to/dep` - The package will be installed from the specified path.
  * `org/package` - The package exists in a private Hex organization. This can be used
    along with all the options above, e.g. `org/package@version`.

  Additionally, a Git ref can be specified when using `git` or `github`:

  * `package@git:git_url@ref`

  ## Options

  * `--only` - Install the requested packages in only a specific environment(s), i.e `--only dev`, `--only dev,test`

  ## Switches

  * `--dry-run` - Run the task without making any changes.
  * `--yes` - Automatically answer yes to any prompts.
  * `--yes-to-deps` - Automatically answer yes to any prompts about installing new deps.
  * `--verbose` - Display additional output from various operations.
  * `--example` - Request that installed packages include initial example code.

  `argv` values are also passed to the igniter installer tasks of installed packages.
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

    argv = Enum.reject(argv, &(&1 in ["--from-igniter-new", "--igniter-repeat"]))

    {argv, positional} = extract_positional_args(argv)

    packages =
      positional
      |> Enum.join(",")
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)

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

Code.put_compiler_option(:ignore_module_conflict, ignore_module_conflict)
