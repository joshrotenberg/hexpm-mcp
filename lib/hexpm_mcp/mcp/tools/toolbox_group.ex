defmodule HexpmMcp.MCP.Tools.ToolboxGroup do
  @moduledoc """
  List the categories in a single Elixir Toolbox group.
  """

  use MCP.Tool.Simple, name: "toolbox_group", description: "List categories in a Toolbox group"

  alias HexpmMcp.Formatter

  argument("group", :string, required: true, description: "Group slug (e.g. \"web\", \"ai\")")

  @impl true
  def call(%{"group" => group}, _context) do
    case HexpmMcp.toolbox_group(group) do
      {:ok, data} ->
        {:ok, MCP.Result.text(Formatter.format_toolbox_group(data))}

      {:error, :not_found} ->
        {:ok, MCP.Result.error("Group not found: #{group}")}

      {:error, reason} ->
        {:ok, MCP.Result.error("Failed to fetch group: #{inspect(reason)}")}
    end
  end
end
