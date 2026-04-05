defmodule HexpmMcp.MCP.Prompts.RecommendPackages do
  @moduledoc "Find and evaluate hex.pm packages for a given use case"

  use Anubis.Server.Component, type: :prompt

  alias Anubis.Server.Response

  schema do
    field(:use_case, :string, required: true, description: "What you need a package for")
  end

  @impl true
  def get_messages(%{use_case: use_case}, frame) do
    response =
      Response.prompt()
      |> Response.user_message("""
      I need hex.pm packages for: #{use_case}

      Use search_packages to find relevant packages, then use package_health_check
      and compare_packages to evaluate the top candidates.

      Provide:
      - Top candidates: 3-5 packages that fit the use case
      - Comparison: Side-by-side evaluation
      - Recommendation: Best choice with rationale
      - Alternatives: When to consider each option
      """)

    {:reply, response, frame}
  end
end
