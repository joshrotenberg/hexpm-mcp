defmodule HexpmMcp.MCP.Tools.Search do
  @moduledoc """
  Search for packages on hex.pm by name/keywords.
  """

  use Snodo.Tool.Simple, name: "search", description: "Search hex.pm packages"

  alias HexpmMcp.Formatter

  argument("query", :string, required: true, description: "Search query string")

  argument("sort", :string,
    description: "Sort by: name, recent_downloads, total_downloads, inserted_at, updated_at"
  )

  argument("page", :integer, description: "Page number (default 1)")

  @impl true
  def call(%{"query" => query} = args, _context) do
    opts =
      []
      |> maybe_put(:sort, Map.get(args, "sort"))
      |> maybe_put(:page, Map.get(args, "page"))

    case HexpmMcp.search(query, opts) do
      {:ok, results} ->
        {:ok, Snodo.Result.text(Formatter.format_search_results(query, results))}

      {:error, reason} ->
        {:ok, Snodo.Result.error("Search failed: #{inspect(reason)}")}
    end
  end

  defp maybe_put(keyword, _key, nil), do: keyword
  defp maybe_put(keyword, key, value), do: Keyword.put(keyword, key, value)
end
