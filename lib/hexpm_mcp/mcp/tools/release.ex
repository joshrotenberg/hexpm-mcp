defmodule HexpmMcp.MCP.Tools.Release do
  @moduledoc """
  Get detailed information about a specific package release.
  """

  use Snodo.Tool.Simple, name: "release", description: "Get detailed package release information"

  alias HexpmMcp.Formatter

  argument("name", :string, required: true, description: "Package name on hex.pm")
  argument("version", :string, required: true, description: "Release version (e.g. \"1.8.5\")")

  @impl true
  def call(%{"name" => name, "version" => version}, _context) do
    case HexpmMcp.get_release(name, version) do
      {:ok, data} ->
        {:ok, Snodo.Result.text(Formatter.format_release(data))}

      {:error, :not_found} ->
        {:ok, Snodo.Result.error("Release #{name} v#{version} not found.")}

      {:error, reason} ->
        {:ok, Snodo.Result.error("Failed to get release: #{inspect(reason)}")}
    end
  end
end
