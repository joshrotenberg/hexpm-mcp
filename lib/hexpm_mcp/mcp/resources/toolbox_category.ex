defmodule HexpmMcp.MCP.Resources.ToolboxCategory do
  @moduledoc "Curated projects in an Elixir Toolbox category"

  use Anubis.Server.Component,
    type: :resource,
    name: "toolbox_category",
    uri_template: "toolbox://{group}/{category}",
    mime_type: "application/json"

  alias Anubis.MCP.Error
  alias Anubis.Server.Response

  @impl true
  def read(%{"group" => group, "category" => category}, frame) do
    case HexpmMcp.toolbox_category(group, category) do
      {:ok, projects} ->
        {:reply, Response.json(Response.resource(), %{projects: projects}), frame}

      {:error, :not_found} ->
        {:error, Error.execution("Category not found: #{group}/#{category}"), frame}

      {:error, reason} ->
        {:error, Error.execution("Failed to fetch category projects: #{inspect(reason)}"), frame}
    end
  end
end
