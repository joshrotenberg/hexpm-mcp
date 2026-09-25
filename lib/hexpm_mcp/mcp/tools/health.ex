defmodule HexpmMcp.MCP.Tools.Health do
  @moduledoc """
  Comprehensive health check for a hex.pm package.
  """

  use MCP.Tool.Simple, name: "health", description: "Run a comprehensive package health check"

  alias HexpmMcp.Formatter

  argument("name", :string, required: true, description: "Package name on hex.pm")

  @impl true
  def call(%{"name" => name}, _context) do
    case HexpmMcp.health_check(name) do
      {:ok, health} ->
        {:ok, MCP.Result.text(Formatter.format_health_check(health))}

      {:error, :not_found} ->
        {:ok, MCP.Result.error("Package '#{name}' not found.")}

      {:error, reason} ->
        {:ok, MCP.Result.error("Health check failed: #{inspect(reason)}")}
    end
  end
end
