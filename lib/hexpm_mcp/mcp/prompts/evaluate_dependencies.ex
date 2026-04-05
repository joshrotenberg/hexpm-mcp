defmodule HexpmMcp.MCP.Prompts.EvaluateDependencies do
  @moduledoc "Evaluate a set of hex.pm dependencies for health and security"

  use Anubis.Server.Component, type: :prompt

  alias Anubis.Server.Response

  schema do
    field(:deps, :string, required: true, description: "Comma-separated package names")
  end

  @impl true
  def get_messages(%{deps: deps}, frame) do
    response =
      Response.prompt()
      |> Response.user_message("""
      Evaluate these hex.pm dependencies: #{deps}

      For each dependency, use package_health_check and audit_dependencies to assess:

      1. Maintenance health: Is it actively maintained? Release cadence?
      2. Security: Any known vulnerabilities? Dependency chain risks?
      3. Bus factor: How many maintainers? Single point of failure?
      4. Staleness: When was the last release? Is it falling behind?

      Provide:
      - Per-dependency health summary
      - Overall dependency stack risk assessment
      - Actionable recommendations (packages to watch, replace, or pin)
      """)

    {:reply, response, frame}
  end
end
