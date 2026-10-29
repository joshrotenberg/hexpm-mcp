defmodule HexpmMcp.MCP.Server do
  @moduledoc """
  Protocol-first MCP server definition for hexpm-mcp.
  """

  # Keep the advertised server version in lockstep with mix.exs. Resolved at
  # compile time and baked in as a literal, so there is no runtime Mix dependency.
  @version Mix.Project.config()[:version]

  # Sent in the initialize result and in server/discover. Clients that defer
  # loading tool definitions show this in place of them, so it names the tools
  # to start with for each task. It sits in context for the whole session, so
  # keep it short.
  @instructions """
  Package data for the Elixir and Erlang ecosystem: hex.pm packages, releases, \
  owners and downloads; HexDocs module and function documentation; OSV.dev \
  security advisories; and the curated Elixir Toolbox catalog.

  Use it when choosing, evaluating, upgrading or auditing a Hex dependency, and \
  to read a package's API on HexDocs instead of recalling it.

  Where to start:
  - Find packages: search, toolbox_search, toolbox_groups, toolbox_trending.
  - Evaluate one: health, then audit, compare, alternatives or dep_tree.
  - A project's dependencies: audit_mix_deps and upgrade_check take the deps \
  list from mix.exs as text.
  - API lookups: docs lists a package's modules, search_docs finds an item, \
  doc_item returns a module's documentation. Pass the version the project \
  locks.

  Resources: hex://{name}/info, hex://{name}/readme, hex://{name}/docs, \
  toolbox://groups, toolbox://{group}/{category}.
  """

  use Snodo.Server,
    name: "hexpm-mcp",
    version: @version,
    instructions: @instructions,
    protocols: [
      Snodo.Protocol.V2026_07_28,
      Snodo.Protocol.V2025_11_25,
      Snodo.Protocol.V2025_06_18
    ],
    schema_validator: Snodo.Schema.Validator.JSV,
    # Every catalog fits on one page. Some clients, Codex 0.157.1 among them,
    # read only the first page of tools/list.
    pagination: [page_size: 100],
    discovery_cache: [ttl_ms: 60_000, scope: "public"],
    tools_cache: [ttl_ms: 60_000, scope: "public"],
    prompts_cache: [ttl_ms: 60_000, scope: "public"],
    resources_cache: [ttl_ms: 60_000, scope: "public"]

  # Basic information tools
  tool(HexpmMcp.MCP.Tools.Search)
  tool(HexpmMcp.MCP.Tools.Info)
  tool(HexpmMcp.MCP.Tools.Versions)
  tool(HexpmMcp.MCP.Tools.Release)
  tool(HexpmMcp.MCP.Tools.Features)
  tool(HexpmMcp.MCP.Tools.Dependencies)
  tool(HexpmMcp.MCP.Tools.Downloads)
  tool(HexpmMcp.MCP.Tools.Owners)
  tool(HexpmMcp.MCP.Tools.Readme)

  # Composite analysis tools
  tool(HexpmMcp.MCP.Tools.Compare)
  tool(HexpmMcp.MCP.Tools.Health)
  tool(HexpmMcp.MCP.Tools.Audit)
  tool(HexpmMcp.MCP.Tools.Alternatives)
  tool(HexpmMcp.MCP.Tools.DepTree)

  # Mix.exs analysis tools
  tool(HexpmMcp.MCP.Tools.AuditMixDeps)
  tool(HexpmMcp.MCP.Tools.UpgradeCheck)

  # HexDocs browsing tools
  tool(HexpmMcp.MCP.Tools.Docs)
  tool(HexpmMcp.MCP.Tools.SearchDocs)
  tool(HexpmMcp.MCP.Tools.DocItem)

  # Elixir Toolbox discovery tools
  tool(HexpmMcp.MCP.Tools.ToolboxGroups)
  tool(HexpmMcp.MCP.Tools.ToolboxGroup)
  tool(HexpmMcp.MCP.Tools.ToolboxCategory)
  tool(HexpmMcp.MCP.Tools.ToolboxTrending)
  tool(HexpmMcp.MCP.Tools.ToolboxSearch)

  # Resources
  resource(HexpmMcp.MCP.Resources.PackageInfo)
  resource(HexpmMcp.MCP.Resources.PackageReadme)
  resource(HexpmMcp.MCP.Resources.PackageDocs)
  resource(HexpmMcp.MCP.Resources.ToolboxGroups)
  resource(HexpmMcp.MCP.Resources.ToolboxCategory)

  # Prompts
  prompt(HexpmMcp.MCP.Prompts.AnalyzePackage)
  prompt(HexpmMcp.MCP.Prompts.ComparePackages)
  prompt(HexpmMcp.MCP.Prompts.EvaluateDependencies)
  prompt(HexpmMcp.MCP.Prompts.RecommendPackages)
  prompt(HexpmMcp.MCP.Prompts.MigrationGuide)
  prompt(HexpmMcp.MCP.Prompts.PackageReview)
end
