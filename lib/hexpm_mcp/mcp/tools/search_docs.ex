defmodule HexpmMcp.MCP.Tools.SearchDocs do
  @moduledoc """
  Search within a package's documentation by name.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.MCP.Error
  alias Anubis.Server.Response
  alias HexpmMcp.Formatter

  schema do
    field(:name, :string, required: true, description: "Package name on hex.pm")
    field(:query, :string, required: true, description: "Search query")
    field(:version, :string, description: "Package version (defaults to latest)")
  end

  @impl true
  def execute(%{name: name, query: query} = args, frame) do
    version = Map.get(args, :version)

    case HexpmMcp.search_docs(name, query, version) do
      {:ok, results} when results != [] ->
        {:reply,
         Response.text(Response.tool(), Formatter.format_search_docs(name, query, results)),
         frame}

      {:ok, []} ->
        {:reply,
         Response.text(Response.tool(), "No results found for '#{query}' in #{name} docs."),
         frame}

      {:error, reason} ->
        {:error, Error.execution("Doc search failed: #{inspect(reason)}"), frame}
    end
  end
end
