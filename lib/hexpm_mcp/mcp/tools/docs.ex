defmodule HexpmMcp.MCP.Tools.Docs do
  @moduledoc """
  Browse package documentation -- module listing.
  """

  use MCP.Tool.Simple, name: "docs", description: "Browse a package documentation module listing"

  alias HexpmMcp.Formatter

  argument("name", :string, required: true, description: "Package name on hex.pm")
  argument("version", :string, description: "Package version (defaults to latest)")

  @impl true
  def call(%{"name" => name} = args, _context) do
    version = Map.get(args, "version")

    case HexpmMcp.get_docs(name, version) do
      {:ok, modules} when modules != [] ->
        {:ok, MCP.Result.text(Formatter.format_docs(name, version, modules))}

      {:ok, []} ->
        {:ok, MCP.Result.text("No modules found for '#{name}'.")}

      {:error, :not_found} ->
        {:ok, MCP.Result.error("Documentation not found for '#{name}'.")}

      {:error, reason} ->
        {:ok, MCP.Result.error("Failed to get docs: #{inspect(reason)}")}
    end
  end
end
