defmodule HexpmMcp.MCP.Tools.Search do
  @moduledoc """
  Search for packages on hex.pm by name/keywords.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.MCP.Error
  alias Anubis.Server.Response
  alias HexpmMcp.Formatter

  schema do
    field(:query, :string, required: true, description: "Search query string")

    field(:sort, :string,
      description: "Sort by: name, recent_downloads, total_downloads, inserted_at, updated_at"
    )

    field(:page, :integer, description: "Page number (default 1)")
  end

  @impl true
  def execute(%{query: query} = args, frame) do
    opts =
      []
      |> maybe_put(:sort, Map.get(args, :sort))
      |> maybe_put(:page, Map.get(args, :page))

    case HexpmMcp.search(query, opts) do
      {:ok, results} ->
        {:reply, Response.text(Response.tool(), Formatter.format_search_results(query, results)),
         frame}

      {:error, reason} ->
        {:error, Error.execution("Search failed: #{inspect(reason)}"), frame}
    end
  end

  defp maybe_put(keyword, _key, nil), do: keyword
  defp maybe_put(keyword, key, value), do: Keyword.put(keyword, key, value)
end
