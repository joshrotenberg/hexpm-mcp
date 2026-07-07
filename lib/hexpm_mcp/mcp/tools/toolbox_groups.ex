defmodule HexpmMcp.MCP.Tools.ToolboxGroups do
  @moduledoc """
  Browse the Elixir Toolbox curated taxonomy of groups and categories.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.MCP.Error
  alias Anubis.Server.Response
  alias HexpmMcp.Formatter

  schema do
  end

  @impl true
  def execute(_args, frame) do
    case HexpmMcp.toolbox_groups() do
      {:ok, groups} ->
        {:reply, Response.text(Response.tool(), Formatter.format_toolbox_groups(groups)), frame}

      {:error, reason} ->
        {:error, Error.execution("Failed to list groups: #{inspect(reason)}"), frame}
    end
  end
end
