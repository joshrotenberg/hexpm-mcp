defmodule HexpmMcp.MCP.Server do
  @moduledoc """
  Anubis MCP server definition for hexpm-mcp.
  """

  # Keep the advertised server version in lockstep with mix.exs. Resolved at
  # compile time and baked in as a literal, so there is no runtime Mix dependency.
  @version Mix.Project.config()[:version]

  use Anubis.Server,
    name: "hexpm-mcp",
    version: @version,
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

  # HexDocs browsing tools
  component(HexpmMcp.MCP.Tools.Docs)
  component(HexpmMcp.MCP.Tools.SearchDocs)
  component(HexpmMcp.MCP.Tools.DocItem)

  # Elixir Toolbox discovery tools
  component(HexpmMcp.MCP.Tools.ToolboxGroups)
  component(HexpmMcp.MCP.Tools.ToolboxGroup)
  component(HexpmMcp.MCP.Tools.ToolboxCategory)
  component(HexpmMcp.MCP.Tools.ToolboxTrending)
  component(HexpmMcp.MCP.Tools.ToolboxSearch)

  # Resources
  component(HexpmMcp.MCP.Resources.PackageInfo)
  component(HexpmMcp.MCP.Resources.PackageReadme)
  component(HexpmMcp.MCP.Resources.PackageDocs)
  component(HexpmMcp.MCP.Resources.ToolboxGroups)
  component(HexpmMcp.MCP.Resources.ToolboxCategory)

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
