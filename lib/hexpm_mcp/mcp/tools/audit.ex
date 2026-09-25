defmodule HexpmMcp.MCP.Tools.Audit do
  @moduledoc """
  Audit a package's dependencies for risks.

  Checks each dependency for retired versions, stale packages,
  single-owner packages, and known vulnerabilities via OSV.dev.
  """

  use MCP.Tool.Simple, name: "audit", description: "Audit package dependencies for risks"

  alias HexpmMcp.Formatter

  argument("name", :string, required: true, description: "Package name on hex.pm")
  argument("version", :string, description: "Release version (defaults to latest)")

  @impl true
  def call(%{"name" => name} = args, _context) do
    version = Map.get(args, "version")

    case HexpmMcp.audit_dependencies(name, version) do
      {:ok, audit} ->
        {:ok, MCP.Result.text(Formatter.format_audit(audit))}

      {:error, :not_found} ->
        {:ok, MCP.Result.error("Package '#{name}' not found.")}

      {:error, reason} ->
        {:ok, MCP.Result.error("Audit failed: #{inspect(reason)}")}
    end
  end
end
