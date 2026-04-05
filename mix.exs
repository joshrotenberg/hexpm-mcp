defmodule HexpmMcp.MixProject do
  use Mix.Project

  def project do
    [
      app: :hexpm_mcp,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      releases: releases()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {HexpmMcp.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:anubis_mcp, "~> 1.0"},
      {:bandit, "~> 1.0"},
      {:req, "~> 0.5"},
      {:floki, "~> 0.37"},
      {:jason, "~> 1.4"},
      {:bypass, "~> 2.1", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
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
