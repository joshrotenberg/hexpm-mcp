defmodule HexpmMcp.MCP.Prompts.AnalyzePackage do
  @moduledoc "Comprehensive analysis of a hex.pm package: quality, maintenance, popularity, and alternatives"

  alias HexpmMcp.MCP.PackageCompletion

  use MCP.Prompt.Simple,
    name: "analyze_package",
    description:
      "Comprehensive analysis of a package's quality, maintenance, popularity, and alternatives",
    completion_arguments: ["name"]

  argument("name", description: "Package name on hex.pm", required: true)

  @impl true
  def complete(%MCP.Completion{argument: "name", value: prefix}, _context) do
    PackageCompletion.complete(prefix)
  end

  @impl true
  def render(%{"name" => name}, _context) do
    {:ok,
     """
     Analyze the hex.pm package "#{name}" comprehensively. Use the available tools to:

     1. Get package info (`info`) for basic metadata
     2. Run `health` for maintenance and risk assessment
     3. Check `downloads` for popularity trends
     4. Look at `dependencies` for complexity
     5. Use `alternatives` to compare options
     6. Run `audit` to check dependencies for vulnerabilities

     Provide a structured report covering:
     - Overview: What the package does and who maintains it
     - Health: Maintenance status, release cadence, bus factor
     - Quality: Documentation, test coverage indicators, API design
     - Popularity: Download trends, reverse dependencies, community adoption
     - Security: Known vulnerabilities, dependency risks
     - Alternatives: How it compares to similar packages
     - Recommendation: Whether to use it, with caveats
     """}
  end
end
