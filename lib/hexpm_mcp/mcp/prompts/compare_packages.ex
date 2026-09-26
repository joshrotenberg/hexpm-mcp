defmodule HexpmMcp.MCP.Prompts.ComparePackages do
  @moduledoc "Compare multiple hex.pm packages side by side"

  use Snodo.Prompt.Simple,
    name: "compare_packages",
    description: "Compare multiple hex.pm packages side by side"

  argument("names", description: "Comma-separated package names (2-5)", required: true)

  @impl true
  def render(%{"names" => names}, _context) do
    {:ok,
     """
     Compare these hex.pm packages: #{names}

     Use `compare` for a side-by-side comparison, then dig deeper with `info`
     and `health` for each package.

     Provide:
     - Comparison table: Downloads, versions, maintenance status, licenses
     - Strengths and weaknesses of each package
     - Use case fit: When you would choose each one
     - Recommendation: Which to prefer and why
     """}
  end
end
