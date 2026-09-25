defmodule HexpmMcp.MCP.Resources.ToolboxGroups do
  @moduledoc "The Elixir Toolbox curated taxonomy of groups and categories"

  use MCP.Resource,
    name: "toolbox_groups",
    description: "The Elixir Toolbox curated taxonomy of groups and categories",
    uri: "toolbox://groups",
    mime_type: "application/json"

  @impl true
  def read(%{"uri" => uri}, _context) do
    case HexpmMcp.toolbox_groups() do
      {:ok, groups} ->
        data = MCP.JSONValue.encodable!(%{groups: groups})
        {:ok, MCP.Result.resource_read(MCP.Resource.json(uri, data))}

      {:error, reason} ->
        {:error, MCP.Error.execution("Failed to list groups: #{inspect(reason)}")}
    end
  end
end
