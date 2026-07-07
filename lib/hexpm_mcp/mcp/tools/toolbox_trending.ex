defmodule HexpmMcp.MCP.Tools.ToolboxTrending do
  @moduledoc """
  List trending Elixir packages from Elixir Toolbox.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.MCP.Error
  alias Anubis.Server.Response
  alias HexpmMcp.Formatter

  schema do
    field(:limit, :integer, description: "Maximum number of projects to return")
  end

  @impl true
  def execute(args, frame) do
    opts = maybe_put([], :limit, Map.get(args, :limit))

    case HexpmMcp.toolbox_trending(opts) do
      {:ok, projects} ->
        {:reply, Response.text(Response.tool(), Formatter.format_toolbox_trending(projects)),
         frame}

      {:error, reason} ->
        {:error, Error.execution("Failed to fetch trending: #{inspect(reason)}"), frame}
    end
  end

  defp maybe_put(keyword, _key, nil), do: keyword
  defp maybe_put(keyword, key, value), do: Keyword.put(keyword, key, value)
end
