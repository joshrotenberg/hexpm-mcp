defmodule HexpmMcp.MCP.Tools.Versions do
  @moduledoc """
  List all versions of a hex.pm package.
  """

  use MCP.Tool.Simple, name: "versions", description: "List all package versions"

  alias HexpmMcp.Formatter

  argument("name", :string, required: true, description: "Package name on hex.pm")

  @impl true
  def call(%{"name" => name}, _context) do
    case HexpmMcp.get_versions(name) do
      {:ok, data} ->
        {:ok, MCP.Result.text(Formatter.format_versions(data))}

      {:error, :not_found} ->
        {:ok, MCP.Result.error("Package '#{name}' not found on hex.pm.")}

      {:error, reason} ->
        {:ok, MCP.Result.error("Failed to get versions: #{inspect(reason)}")}
    end
  end
end
