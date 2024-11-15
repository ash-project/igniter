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
  * `package@path:path/to/dep` - The package will be installed from the specified path.
  * `org/package` - The package exists in a private Hex organization. This can be used
    along with all the options above, e.g. `org/package@version`.
  * `repo:package` - The package exists in a private Hex repo. This can b e used along
    with all the options above, e.g. `repo:package@version`.

  If you are specifying a private repo and organization, the repo must come first:

      mix igniter.install repo:org/package@version

  Additionally, a Git ref can be specified when using `git` or `github`:

  * `package@git:git_url@ref`

  ## Switches

  * `--dry-run` - Run the task without making any changes.
  * `--yes` - Automatically answer yes to any prompts.
  * `--example` - Request that installed packages include initial example code.
  """
  use Mix.Task

  @requirements "deps.compile"

  @impl true
  @shortdoc "Install a package or packages, and run any associated installers."
  def run(argv) do
    Mix.Task.run("compile", ["--no-compile"])

    {argv, positional} = Installer.Lib.Private.SharedUtils.extract_positional_args(argv)

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
end
