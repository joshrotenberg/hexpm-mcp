defmodule HexpmMcp.MCP.Tools.ToolboxTrending do
  @moduledoc """
  List trending Elixir packages from Elixir Toolbox.
  """

  use Snodo.Tool.Simple, name: "toolbox_trending", description: "List trending Elixir packages"

  alias HexpmMcp.Formatter

  argument("limit", :integer, description: "Maximum number of projects to return")

  @impl true
  def call(args, _context) do
    opts = maybe_put([], :limit, Map.get(args, "limit"))

    case HexpmMcp.toolbox_trending(opts) do
      {:ok, projects} ->
        {:ok, Snodo.Result.text(Formatter.format_toolbox_trending(projects))}

      {:error, reason} ->
        {:ok, Snodo.Result.error("Failed to fetch trending: #{inspect(reason)}")}
    end
  end

  defp maybe_put(keyword, _key, nil), do: keyword
  defp maybe_put(keyword, key, value), do: Keyword.put(keyword, key, value)
end
