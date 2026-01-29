defmodule NervesMCP.MixProject do
  use Mix.Project

  def project do
    [
      app: :nerves_mcp,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "Nerves mcp",
      description: "TODO: write a proper description",
      docs: docs(),
      package: package(),
      aliases: aliases(),
      dialyzer: dialyzer()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {NervesMCP.Application, []}
    ]
  end

  def docs do
    [
      main: "readme",
      extras: ["README.md"]
    ]
  end

  def package do
    [
      name: :nerves_mcp,
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/TODO/nerves_mcp"}
    ]
  end

  def aliases do
    [
      check: [
        "hex.audit",
        "compile --warnings-as-errors --force",
        "format --check-formatted",
        "credo",
        "deps.unlock --check-unused",
        "spellweaver.check",
        "dialyzer"
      ]
    ]
  end

  def dialyzer do
    [
      plt_add_apps: [:mix],
      ignore_warnings: ".dialyzer_ignore.exs"
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:anubis_mcp, "~> 0.17"},
      {:bandit, "~> 1.0"},
      {:circuits_uart, "~> 1.0"},
      {:nstandard, "~> 0.1"},
      {:igniter, "~> 0.6", only: [:dev, :test]},
      {:ex_doc, "~> 0.31", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:spellweaver, "~> 0.1", only: [:dev, :test], runtime: false}
    ]
  end
end
