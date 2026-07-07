defmodule HexpmMcp.MixProject do
  use Mix.Project

  @source_url "https://github.com/joshrotenberg/hexpm-mcp"

  def project do
    [
      app: :hexpm_mcp,
      version: "0.3.3",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      releases: releases(),
      description: description(),
      package: package(),
      source_url: @source_url,
      docs: docs(),
      test_coverage: [tool: ExCoveralls]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {HexpmMcp.Application, []}
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test,
        "coveralls.json": :test
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp description do
    "MCP server for hex.pm and hexdocs.pm: search, inspect, compare, audit, and " <>
      "discover Elixir/Erlang packages, browse docs, and check dependencies for vulnerabilities."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      maintainers: ["Josh Rotenberg"],
      files: ~w(lib mix.exs README.md CHANGELOG.md LICENSE .formatter.exs)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md"],
      source_url: @source_url
    ]
  end

  defp deps do
    [
      {:anubis_mcp, "~> 1.0"},
      {:bandit, "~> 1.0"},
      {:req, "~> 0.6"},
      {:floki, "~> 0.37"},
      {:jason, "~> 1.4"},
      {:bypass, "~> 2.1", only: :test},
      {:excoveralls, "~> 0.18", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false}
    ]
  end

  defp releases do
    [
      hexpm_mcp: [
        applications: [runtime_tools: :permanent]
      ]
    ]
  end
end
