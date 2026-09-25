defmodule HexpmMcp.MCP.Tools.ToolboxSearch do
  @moduledoc """
  Search packages via Elixir Toolbox. Results carry GitHub/GitLab stats,
  popularity, and health signals not exposed by the raw hex.pm search.
  """

  use Snodo.Tool.Simple,
    name: "toolbox_search",
    description: "Search packages through Elixir Toolbox"

  alias HexpmMcp.Formatter

  argument("query", :string, required: true, description: "Search query string")

  @impl true
  def call(%{"query" => query}, _context) do
    case HexpmMcp.toolbox_search(query) do
      {:ok, results} ->
        {:ok, Snodo.Result.text(Formatter.format_toolbox_search(query, results))}

      {:error, reason} ->
        {:ok, Snodo.Result.error("Search failed: #{inspect(reason)}")}
    end
  end
end
