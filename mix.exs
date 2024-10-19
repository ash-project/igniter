defmodule Igniter.MixProject do
  use Mix.Project

  @version "0.3.67"

  @description """
  A code generation and project patching framework
  """

  def project do
    [
      app: :igniter,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      description: @description,
      aliases: aliases(),
      package: package(),
      docs: docs(),
      deps: deps()
    ]
  end

  defp elixirc_paths(:test) do
    elixirc_paths(:dev) ++ ["test/support"]
  end

  defp elixirc_paths(_env) do
    ["lib", "installer/lib/private"]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :public_key, :ssl, :inets, :eex]
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: "https://github.com/ash-project/igniter",
      logo: "logos/igniter-logo-small.png",
      extra_section: "GUIDES",
      extras: [
        {"README.md", title: "Home"},
        "documentation/writing-generators.md",
        "documentation/configuring-igniter.md",
        "documentation/upgrades.md",
        "CHANGELOG.md"
      ],
      before_closing_head_tag: fn type ->
        if type == :html do
          """
          <script>
            if (location.hostname === "hexdocs.pm") {
              var script = document.createElement("script");
              script.src = "https://plausible.io/js/script.js";
              script.setAttribute("defer", "defer")
              script.setAttribute("data-domain", "ashhexdocs")
              document.head.appendChild(script);
            }
          </script>
          """
        end
      end
    ]
  end

  defp package do
    [
      name: :igniter,
      licenses: ["MIT"],
      files: ~w(lib installer/lib/private .formatter.exs mix.exs README* LICENSE*
      CHANGELOG*),
      links: %{
        GitHub: "https://github.com/ash-project/igniter",
        Discord: "https://discord.gg/HTHRaaVPUc",
        Website: "https://ash-hq.org",
        Forum: "https://elixirforum.com/c/elixir-framework-forums/ash-framework-forum"
      }
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:rewrite, "~> 0.9"},
      {:glob_ex, "~> 0.1.7"},
      {:spitfire, "~> 0.1 and >= 0.1.3"},
      {:sourceror, "~> 1.4"},
      {:jason, "~> 1.4"},
      # Dev/Test dependencies
      {:eflame, "~> 1.0", only: [:dev, :test]},
      {:ex_doc, "~> 0.32", only: [:dev, :test], runtime: false},
      {:ex_check, "~> 0.12", only: [:dev, :test]},
      {:credo, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:dialyxir, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:mimic, "~> 1.7", only: [:test]},
      {:git_ops, "~> 2.5", only: [:dev, :test]},
      {:mix_audit, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:mix_test_watch, "~> 1.0", only: [:dev, :test], runtime: false},
      {:benchee, "~> 1.1", only: [:dev, :test]},
      {:doctor, "~> 0.21", only: [:dev, :test]}
    ]
  end

  defp aliases do
    [
      credo: "credo --strict"
    ]
  end
end
