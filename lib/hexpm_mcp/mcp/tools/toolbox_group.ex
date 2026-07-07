defmodule HexpmMcp.MCP.Tools.ToolboxGroup do
  @moduledoc """
  List the categories in a single Elixir Toolbox group.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.MCP.Error
  alias Anubis.Server.Response
  alias HexpmMcp.Formatter

  schema do
    field(:group, :string, required: true, description: "Group slug (e.g. \"web\", \"ai\")")
  end

  @impl true
  def execute(%{group: group}, frame) do
    case HexpmMcp.toolbox_group(group) do
      {:ok, data} ->
        {:reply, Response.text(Response.tool(), Formatter.format_toolbox_group(data)), frame}

      {:error, :not_found} ->
        {:error, Error.execution("Group not found: #{group}"), frame}

      {:error, reason} ->
        {:error, Error.execution("Failed to fetch group: #{inspect(reason)}"), frame}
    end
  end
end
