defmodule HexpmMcp.MCP.Prompts.AnalyzePackage do
  @moduledoc "Comprehensive analysis of a hex.pm package: quality, maintenance, popularity, and alternatives"

  use Anubis.Server.Component, type: :prompt

  alias Anubis.Server.Response

  schema do
    field(:name, :string, required: true, description: "Package name on hex.pm")
  end

  @impl true
  def get_messages(%{name: name}, frame) do
    response =
      Response.prompt()
      |> Response.user_message("""
      Analyze the hex.pm package "#{name}" comprehensively. Use the available tools to:

      1. Get package info (get_package_info) for basic metadata
      2. Run a health check (package_health_check) for maintenance and risk assessment
      3. Check download trends (get_downloads) for popularity
      4. Look at the dependency list (get_dependencies) for complexity
      5. Find alternatives (find_alternatives) to compare options
      6. Check for vulnerabilities (audit_dependencies) for security

      Provide a structured report covering:
      - Overview: What the package does and who maintains it
      - Health: Maintenance status, release cadence, bus factor
      - Quality: Documentation, test coverage indicators, API design
      - Popularity: Download trends, reverse dependencies, community adoption
      - Security: Known vulnerabilities, dependency risks
      - Alternatives: How it compares to similar packages
      - Recommendation: Whether to use it, with caveats
      """)

    {:reply, response, frame}
  end
end
