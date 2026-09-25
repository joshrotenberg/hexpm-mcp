defmodule HexpmMcp.MCP.Prompts.EvaluateDependencies do
  @moduledoc "Evaluate a set of hex.pm dependencies for health and security"

  use MCP.Prompt.Simple,
    name: "evaluate_dependencies",
    description: "Evaluate a set of hex.pm dependencies for health and security"

  argument("deps", description: "Comma-separated package names", required: true)

  @impl true
  def render(%{"deps" => deps}, _context) do
    {:ok,
     """
     Evaluate these hex.pm dependencies: #{deps}

     For each dependency, use `health` and `audit` to assess:

     1. Maintenance health: Is it actively maintained? Release cadence?
     2. Security: Any known vulnerabilities? Dependency chain risks?
     3. Bus factor: How many maintainers? Single point of failure?
     4. Staleness: When was the last release? Is it falling behind?

     Provide:
     - Per-dependency health summary
     - Overall dependency stack risk assessment
     - Actionable recommendations (packages to watch, replace, or pin)
     """}
  end
end
