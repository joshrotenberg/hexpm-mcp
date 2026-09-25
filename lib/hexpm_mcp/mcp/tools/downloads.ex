defmodule HexpmMcp.MCP.Tools.Downloads do
  @moduledoc """
  Get download statistics for a hex.pm package.
  """

  use MCP.Tool.Simple, name: "downloads", description: "Get package download statistics"

  alias HexpmMcp.Formatter

  argument("name", :string, required: true, description: "Package name on hex.pm")

  @impl true
  def call(%{"name" => name}, _context) do
    case HexpmMcp.get_downloads(name) do
      {:ok, data} ->
        {:ok, MCP.Result.text(Formatter.format_downloads(data))}

      {:error, :not_found} ->
        {:ok, MCP.Result.error("Package '#{name}' not found.")}

      {:error, reason} ->
        {:ok, MCP.Result.error("Failed to get downloads: #{inspect(reason)}")}
    end
  end
end
