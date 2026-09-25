defmodule HexpmMcp.MCP.Prompts.RecommendPackages do
  @moduledoc "Find and evaluate hex.pm packages for a given use case"

  use MCP.Prompt,
    name: "recommend_packages",
    description: "Find and evaluate hex.pm packages for a given use case",
    arguments: [
      %{
        "name" => "use_case",
        "description" => "What you need a package for",
        "required" => true
      }
    ]

  @impl true
  def render(%{"use_case" => use_case}, _context) do
    message =
      MCP.Prompt.message(
        :user,
        MCP.Prompt.text("""
        I need hex.pm packages for: #{use_case}

        Use `search` to find relevant packages, then use `health` and `compare`
        to evaluate the top candidates.

        Provide:
        - Top candidates: 3-5 packages that fit the use case
        - Comparison: Side-by-side evaluation
        - Recommendation: Best choice with rationale
        - Alternatives: When to consider each option
        """)
      )

    {:ok, MCP.Result.prompt_get(message)}
  end
end
