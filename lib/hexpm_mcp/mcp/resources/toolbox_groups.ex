defmodule HexpmMcp.MCP.Resources.ToolboxGroups do
  @moduledoc "The Elixir Toolbox curated taxonomy of groups and categories"

  use Anubis.Server.Component,
    type: :resource,
    name: "toolbox_groups",
    uri: "toolbox://groups",
    mime_type: "application/json"

  alias Anubis.MCP.Error
  alias Anubis.Server.Response

  @impl true
  def read(_params, frame) do
    case HexpmMcp.toolbox_groups() do
      {:ok, groups} ->
        {:reply, Response.json(Response.resource(), %{groups: groups}), frame}

      {:error, reason} ->
        {:error, Error.execution("Failed to list groups: #{inspect(reason)}"), frame}
    end
  end
end
