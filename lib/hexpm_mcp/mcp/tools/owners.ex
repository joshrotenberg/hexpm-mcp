defmodule HexpmMcp.MCP.Tools.Owners do
  @moduledoc """
  Get owners/maintainers of a hex.pm package.
  """

  use MCP.Tool.Simple, name: "owners", description: "Get package owners and maintainers"

  alias HexpmMcp.Formatter

  argument("name", :string, required: true, description: "Package name on hex.pm")

  @impl true
  def call(%{"name" => name}, _context) do
    case HexpmMcp.get_owners(name) do
      {:ok, owners} ->
        {:ok, MCP.Result.text(Formatter.format_owners(name, owners))}

      {:error, :not_found} ->
        {:ok, MCP.Result.error("Package '#{name}' not found.")}

      {:error, reason} ->
        {:ok, MCP.Result.error("Failed to get owners: #{inspect(reason)}")}
    end
  end
end
