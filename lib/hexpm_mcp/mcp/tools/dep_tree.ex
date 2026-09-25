defmodule HexpmMcp.MCP.Tools.DepTree do
  @moduledoc """
  Get the full transitive dependency tree for a package (BFS, max depth 5).
  """

  use Snodo.Tool.Simple, name: "dep_tree", description: "Build a package dependency tree"

  alias HexpmMcp.Formatter

  argument("name", :string, required: true, description: "Package name on hex.pm")
  argument("version", :string, description: "Release version (defaults to latest)")
  argument("max_depth", :integer, description: "Maximum depth to traverse (default 5, max 5)")

  @impl true
  def call(%{"name" => name} = args, _context) do
    version = Map.get(args, "version")
    opts = if max_depth = Map.get(args, "max_depth"), do: [max_depth: max_depth], else: []

    case HexpmMcp.dependency_tree(name, version, opts) do
      {:ok, data} ->
        {:ok, Snodo.Result.text(Formatter.format_dependency_tree(data))}

      {:error, :not_found} ->
        {:ok, Snodo.Result.error("Package '#{name}' not found.")}

      {:error, reason} ->
        {:ok, Snodo.Result.error("Failed to build dependency tree: #{inspect(reason)}")}
    end
  end
end
