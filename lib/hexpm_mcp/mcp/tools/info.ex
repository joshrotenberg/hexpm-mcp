defmodule HexpmMcp.MCP.Tools.Info do
  @moduledoc """
  Get detailed information about a hex.pm package.
  """

  use Snodo.Tool.Simple, name: "info", description: "Get detailed package information"

  alias HexpmMcp.Formatter

  argument("name", :string, required: true, description: "Package name on hex.pm")

  @impl true
  def call(%{"name" => name}, _context) do
    case HexpmMcp.get_info(name) do
      {:ok, info} ->
        {:ok, Snodo.Result.text(Formatter.format_package_info(info))}

      {:error, :not_found} ->
        {:ok, Snodo.Result.error("Package '#{name}' not found on hex.pm.")}

      {:error, reason} ->
        {:ok, Snodo.Result.error("Failed to get package info: #{inspect(reason)}")}
    end
  end
end
