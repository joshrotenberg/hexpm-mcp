defmodule HexpmMcp.MCP.Resources.ToolboxCategory do
  @moduledoc "Curated projects in an Elixir Toolbox category"

  use MCP.Resource.Simple,
    name: "toolbox_category",
    description: "Curated projects in an Elixir Toolbox category",
    uri_template: "toolbox://{group}/{category}",
    mime_type: "application/json"

  @impl true
  def read(%{"uri" => uri, "group" => group, "category" => category}, _context) do
    case HexpmMcp.toolbox_category(group, category) do
      {:ok, projects} ->
        {:ok, MCP.JSONValue.encodable!(%{projects: projects})}

      {:error, :not_found} ->
        {:error, MCP.Error.invalid_params("Resource not found", %{"uri" => uri})}

      {:error, reason} ->
        {:error, MCP.Error.execution("Failed to fetch category projects: #{inspect(reason)}")}
    end
  end
end
