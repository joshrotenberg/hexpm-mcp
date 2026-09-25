defmodule HexpmMcp.MCP.Resources.ToolboxCategory do
  @moduledoc "Curated projects in an Elixir Toolbox category"

  use Snodo.Resource.Simple,
    name: "toolbox_category",
    description: "Curated projects in an Elixir Toolbox category",
    uri_template: "toolbox://{group}/{category}",
    mime_type: "application/json"

  @impl true
  def read(%{"uri" => uri, "group" => group, "category" => category}, _context) do
    case HexpmMcp.toolbox_category(group, category) do
      {:ok, projects} ->
        {:ok, Snodo.JSONValue.encodable!(%{projects: projects})}

      {:error, :not_found} ->
        {:error, Snodo.Error.invalid_params("Resource not found", %{"uri" => uri})}

      {:error, reason} ->
        {:error, Snodo.Error.execution("Failed to fetch category projects: #{inspect(reason)}")}
    end
  end
end
