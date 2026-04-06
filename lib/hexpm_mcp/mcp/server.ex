defmodule HexpmMcp.MCP.Server do
  @moduledoc """
  Anubis MCP server definition for hexpm-mcp.
  """

  use Anubis.Server,
    name: "hexpm-mcp",
    version: "0.1.0",
    capabilities: [
      :tools,
      :resources,
      :prompts
    ]

  # Basic information tools
  component(HexpmMcp.MCP.Tools.Search)
  component(HexpmMcp.MCP.Tools.Info)
  component(HexpmMcp.MCP.Tools.Versions)
  component(HexpmMcp.MCP.Tools.Release)
  component(HexpmMcp.MCP.Tools.Features)
  component(HexpmMcp.MCP.Tools.Dependencies)
  component(HexpmMcp.MCP.Tools.Reverse)
  component(HexpmMcp.MCP.Tools.Downloads)
  component(HexpmMcp.MCP.Tools.Owners)
  component(HexpmMcp.MCP.Tools.Readme)

  # Composite analysis tools
  component(HexpmMcp.MCP.Tools.Compare)
  component(HexpmMcp.MCP.Tools.Health)
  component(HexpmMcp.MCP.Tools.Audit)
  component(HexpmMcp.MCP.Tools.Alternatives)
  component(HexpmMcp.MCP.Tools.DepTree)

  # Mix.exs analysis tools
  component(HexpmMcp.MCP.Tools.AuditMixDeps)
  component(HexpmMcp.MCP.Tools.UpgradeCheck)

  # Resources
  component(HexpmMcp.MCP.Resources.PackageInfo)
  component(HexpmMcp.MCP.Resources.PackageReadme)
  component(HexpmMcp.MCP.Resources.PackageDocs)

  # Prompts
  component(HexpmMcp.MCP.Prompts.AnalyzePackage)
  component(HexpmMcp.MCP.Prompts.ComparePackages)
  component(HexpmMcp.MCP.Prompts.EvaluateDependencies)
  component(HexpmMcp.MCP.Prompts.RecommendPackages)
  component(HexpmMcp.MCP.Prompts.MigrationGuide)

  @impl true
  def init(_client_info, frame) do
    {:ok, frame}
  end
end
