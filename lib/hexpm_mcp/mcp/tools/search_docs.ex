defmodule HexpmMcp.MCP.Tools.SearchDocs do
  @moduledoc """
  Search within a package's documentation by name.
  """

  use Snodo.Tool.Simple, name: "search_docs", description: "Search within package documentation"

  alias HexpmMcp.Formatter

  argument("name", :string, required: true, description: "Package name on hex.pm")
  argument("query", :string, required: true, description: "Search query")
  argument("version", :string, description: "Package version (defaults to latest)")

  @impl true
  def call(%{"name" => name, "query" => query} = args, _context) do
    version = Map.get(args, "version")

    case HexpmMcp.search_docs(name, query, version) do
      {:ok, results} when results != [] ->
        {:ok, Snodo.Result.text(Formatter.format_search_docs(name, query, results))}

      {:ok, []} ->
        {:ok, Snodo.Result.text("No results found for '#{query}' in #{name} docs.")}

      {:error, reason} ->
        {:ok, Snodo.Result.error("Doc search failed: #{inspect(reason)}")}
    end
  end
end
