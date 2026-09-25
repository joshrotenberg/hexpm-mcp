defmodule HexpmMcp.MCP.Tools.Dependencies do
  @moduledoc """
  Get dependencies for a package version.
  """

  use Snodo.Tool.Simple,
    name: "dependencies",
    description: "Get dependencies for a package version"

  alias HexpmMcp.Formatter

  argument("name", :string, required: true, description: "Package name on hex.pm")
  argument("version", :string, description: "Release version (defaults to latest)")

  @impl true
  def call(%{"name" => name} = args, _context) do
    version = Map.get(args, "version")

    case HexpmMcp.get_dependencies(name, version) do
      {:ok, data} ->
        {:ok, Snodo.Result.text(Formatter.format_dependencies(data))}

      {:error, :not_found} ->
        {:ok, Snodo.Result.error("Package '#{name}' not found.")}

      {:error, reason} ->
        {:ok, Snodo.Result.error("Failed to get dependencies: #{inspect(reason)}")}
    end
  end
end
