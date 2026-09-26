defmodule HexpmMcp.MCP.Tools.ToolboxGroups do
  @moduledoc """
  Browse the Elixir Toolbox curated taxonomy of groups and categories.
  """

  use Snodo.Tool.Simple, name: "toolbox_groups", description: "Browse the Elixir Toolbox taxonomy"

  alias HexpmMcp.Formatter

  # Preserve the original zero-argument wire schema without adding properties.
  input_schema(%{"type" => "object"})

  @impl true
  def call(_args, _context) do
    case HexpmMcp.toolbox_groups() do
      {:ok, groups} ->
        {:ok, Snodo.Result.text(Formatter.format_toolbox_groups(groups))}

      {:error, reason} ->
        {:ok, Snodo.Result.error("Failed to list groups: #{inspect(reason)}")}
    end
  end
end
