defmodule HexpmMcp.MCP.Prompts.ComparePackages do
  @moduledoc "Compare multiple hex.pm packages side by side"

  use Anubis.Server.Component, type: :prompt

  alias Anubis.Server.Response

  schema do
    field(:names, :string, required: true, description: "Comma-separated package names (2-5)")
  end

  @impl true
  def get_messages(%{names: names}, frame) do
    response =
      Response.prompt()
      |> Response.user_message("""
      Compare these hex.pm packages: #{names}

      Use the compare_packages tool for a side-by-side comparison, then dig deeper with
      get_package_info and package_health_check for each package.

      Provide:
      - Comparison table: Downloads, versions, maintenance status, licenses
      - Strengths and weaknesses of each package
      - Use case fit: When you would choose each one
      - Recommendation: Which to prefer and why
      """)

    {:reply, response, frame}
  end
end
