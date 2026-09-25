defmodule HexpmMcp.MCP.Tools.Alternatives do
  @moduledoc """
  Find and compare alternative packages for a given hex.pm package.
  """

  use MCP.Tool.Simple, name: "alternatives", description: "Find alternative packages"

  alias HexpmMcp.Formatter

  argument("name", :string, required: true, description: "Package name on hex.pm")

  @impl true
  def call(%{"name" => name}, _context) do
    case HexpmMcp.find_alternatives(name) do
      {:ok, data} ->
        {:ok, MCP.Result.text(Formatter.format_alternatives(data))}

      {:error, :not_found} ->
        {:ok, MCP.Result.error("Package '#{name}' not found.")}

      {:error, reason} ->
        {:ok, MCP.Result.error("Failed to find alternatives: #{inspect(reason)}")}
    end
  end
end
