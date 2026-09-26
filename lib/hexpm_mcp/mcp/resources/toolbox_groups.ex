defmodule HexpmMcp.MCP.Resources.ToolboxGroups do
  @moduledoc "The Elixir Toolbox curated taxonomy of groups and categories"

  use Snodo.Resource.Simple,
    name: "toolbox_groups",
    description: "The Elixir Toolbox curated taxonomy of groups and categories",
    uri: "toolbox://groups",
    mime_type: "application/json"

  @impl true
  def read(_params, _context) do
    case HexpmMcp.toolbox_groups() do
      {:ok, groups} ->
        {:ok, Snodo.JSONValue.encodable!(%{groups: groups})}

      {:error, reason} ->
        {:error, Snodo.Error.execution("Failed to list groups: #{inspect(reason)}")}
    end
  end
end
