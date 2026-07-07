defmodule HexpmMcp.MCP.Tools.ToolboxSearch do
  @moduledoc """
  Search packages via Elixir Toolbox. Results carry GitHub/GitLab stats,
  popularity, and health signals not exposed by the raw hex.pm search.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.MCP.Error
  alias Anubis.Server.Response
  alias HexpmMcp.Formatter

  schema do
    field(:query, :string, required: true, description: "Search query string")
  end

  @impl true
  def execute(%{query: query}, frame) do
    case HexpmMcp.toolbox_search(query) do
      {:ok, results} ->
        {:reply, Response.text(Response.tool(), Formatter.format_toolbox_search(query, results)),
         frame}

      {:error, reason} ->
        {:error, Error.execution("Search failed: #{inspect(reason)}"), frame}
    end
  end
end
