defmodule Igniter.New.MixProject do
  use Mix.Project

  @version "0.5.31"
  @scm_url "https://github.com/ash-project/igniter"

  def project do
    [
      app: :igniter_new,
      start_permanent: Mix.env() == :prod,
      version: @version,
      elixir: "~> 1.14",
      deps: deps(),
      package: [
        maintainers: ["Zach Daniel"],
        licenses: ["MIT"],
        links: %{"GitHub" => @scm_url},
        files: ~w(lib mix.exs README.md priv)
      ],
      preferred_cli_env: [docs: :docs],
      source_url: @scm_url,
      docs: docs(),
      aliases: aliases(),
      homepage_url: "https://www.ash-hq.org",
      description: """
      Create a new mix project with igniter, and run igniter installers in one command!
      """
    ]
  end

  def application do
    [
      extra_applications: [:hex, :eex, :crypto, :public_key]
    ]
  end

  def deps do
    [
      {:ex_doc, "~> 0.24", only: [:dev, :test], runtime: false}
    ]
  end

  defp docs do
    [
      source_url_pattern: "#{@scm_url}/blob/v#{@version}/installer/%{path}#L%{line}"
    ]
  end

  defp aliases do
    [
      copy_docs: [
        "compile",
        fn _argv ->
          Igniter.Installer.TaskHelpers.copy_docs()
          Mix.Task.reenable("compile")
          Mix.Task.run("compile")
        end
      ],
      docs: [
        "copy_docs",
        "docs"
      ]
    ]
  end
end
