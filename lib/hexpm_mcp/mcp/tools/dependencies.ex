defmodule HexpmMcp.MCP.Tools.Dependencies do
  @moduledoc """
  Get dependencies for a package version.
  """

  use MCP.Tool.Simple, name: "dependencies", description: "Get dependencies for a package version"

  alias HexpmMcp.Formatter

  argument("name", :string, required: true, description: "Package name on hex.pm")
  argument("version", :string, description: "Release version (defaults to latest)")

  @impl true
  def call(%{"name" => name} = args, _context) do
    version = Map.get(args, "version")

    case HexpmMcp.get_dependencies(name, version) do
      {:ok, data} ->
        {:ok, MCP.Result.text(Formatter.format_dependencies(data))}

      {:error, :not_found} ->
        {:ok, MCP.Result.error("Package '#{name}' not found.")}

      {:error, reason} ->
        {:ok, MCP.Result.error("Failed to get dependencies: #{inspect(reason)}")}
    end
  end
end
