defmodule HexpmMcp.MCP.Prompts.ComparePackages do
  @moduledoc "Compare multiple hex.pm packages side by side"

  use MCP.Prompt,
    name: "compare_packages",
    description: "Compare multiple hex.pm packages side by side",
    arguments: [
      %{
        "name" => "names",
        "description" => "Comma-separated package names (2-5)",
        "required" => true
      }
    ]

  @impl true
  def render(%{"names" => names}, _context) do
    message =
      MCP.Prompt.message(
        :user,
        MCP.Prompt.text("""
        Compare these hex.pm packages: #{names}

        Use `compare` for a side-by-side comparison, then dig deeper with `info`
        and `health` for each package.

        Provide:
        - Comparison table: Downloads, versions, maintenance status, licenses
        - Strengths and weaknesses of each package
        - Use case fit: When you would choose each one
        - Recommendation: Which to prefer and why
        """)
      )

    {:ok, MCP.Result.prompt_get(message)}
  end
end
