defmodule HexpmMcp.MCP.Tools.Features do
  @moduledoc """
  Get optional features/extras for a package release.
  """

  use MCP.Tool.Simple,
    name: "features",
    description: "Get optional features for a package release"

  alias HexpmMcp.Formatter

  argument("name", :string, required: true, description: "Package name on hex.pm")
  argument("version", :string, description: "Release version (defaults to latest)")

  @impl true
  def call(%{"name" => name} = args, _context) do
    version = Map.get(args, "version")

    case HexpmMcp.get_features(name, version) do
      {:ok, data} ->
        {:ok, MCP.Result.text(Formatter.format_features(data))}

      {:error, :not_found} ->
        {:ok, MCP.Result.error("Package '#{name}' not found.")}

      {:error, reason} ->
        {:ok, MCP.Result.error("Failed to get features: #{inspect(reason)}")}
    end
  end
end
