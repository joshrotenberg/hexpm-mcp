defmodule HexpmMcp.MCP.Resources.ToolboxCategory do
  @moduledoc "Curated projects in an Elixir Toolbox category"

  use MCP.Resource,
    name: "toolbox_category",
    description: "Curated projects in an Elixir Toolbox category",
    uri_template: "toolbox://{group}/{category}",
    mime_type: "application/json"

  @impl true
  def read(%{"uri" => uri, "group" => group, "category" => category}, _context) do
    case HexpmMcp.toolbox_category(group, category) do
      {:ok, projects} ->
        data = MCP.JSONValue.encodable!(%{projects: projects})
        {:ok, MCP.Result.resource_read(MCP.Resource.json(uri, data))}

      {:error, :not_found} ->
        {:error, MCP.Error.invalid_params("Resource not found", %{"uri" => uri})}

      {:error, reason} ->
        {:error, MCP.Error.execution("Failed to fetch category projects: #{inspect(reason)}")}
    end
  end
end
