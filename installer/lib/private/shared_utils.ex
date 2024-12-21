defmodule Installer.Lib.Private.SharedUtils do
  @moduledoc false

  def igniter_install_docs do
    """
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
    * `--example` - Request that installed packages include initial example code.
    """
  end

  def igniter_version, do: "~> 0.5"

  def install(argv) do
    Mix.Task.run("compile", ["--no-compile"])

    {argv, positional} = extract_positional_args(argv)

    packages =
      positional
      |> Enum.join(",")
      |> String.split(",", trim: true)

    if Enum.empty?(packages) do
      raise ArgumentError, "must provide at least one package to install"
    end

    Application.ensure_all_started(:rewrite)

    apply(Igniter.Util.Install, :install, [Enum.join(packages, ","), argv])
  end

  @doc false
  def extract_positional_args(argv) do
    do_extract_positional_args(argv, [], [])
  end

  def do_extract_positional_args([], argv, positional), do: {argv, positional}

  def do_extract_positional_args(argv, got_argv, positional) do
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

  def reevaluate_mix_exs() do
    old_undefined = Code.get_compiler_option(:no_warn_undefined)
    old_relative_paths = Code.get_compiler_option(:relative_paths)
    old_ignore_module_conflict = Code.get_compiler_option(:ignore_module_conflict)

    try do
      Code.compiler_options(
        relative_paths: false,
        no_warn_undefined: :all,
        ignore_module_conflict: true
      )

      _ = Code.compile_file("mix.exs")
    after
      Code.compiler_options(
        relative_paths: old_relative_paths,
        no_warn_undefined: old_undefined,
        ignore_module_conflict: old_ignore_module_conflict
      )
    end
  end
end
