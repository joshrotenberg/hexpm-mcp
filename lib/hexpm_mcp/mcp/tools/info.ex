defmodule HexpmMcp.MCP.Tools.Info do
  @moduledoc """
  Get detailed information about a hex.pm package.
  """

  use MCP.Tool.Simple, name: "info", description: "Get detailed package information"

  alias HexpmMcp.Formatter

  argument("name", :string, required: true, description: "Package name on hex.pm")

  @impl true
  def call(%{"name" => name}, _context) do
    case HexpmMcp.get_info(name) do
      {:ok, info} ->
        {:ok, MCP.Result.text(Formatter.format_package_info(info))}

      {:error, :not_found} ->
        {:ok, MCP.Result.error("Package '#{name}' not found on hex.pm.")}

      {:error, reason} ->
        {:ok, MCP.Result.error("Failed to get package info: #{inspect(reason)}")}
    end
  end
end
