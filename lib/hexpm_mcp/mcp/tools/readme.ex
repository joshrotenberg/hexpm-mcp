defmodule HexpmMcp.MCP.Tools.Readme do
  @moduledoc """
  Get the README content for a hex.pm package.
  """

  use Snodo.Tool.Simple, name: "readme", description: "Get package README content"

  argument("name", :string, required: true, description: "Package name on hex.pm")
  argument("version", :string, description: "Package version (defaults to latest)")

  @impl true
  def call(%{"name" => name} = args, _context) do
    version = Map.get(args, "version")

    case HexpmMcp.get_readme(name, version) do
      {:ok, content} ->
        {:ok, Snodo.Result.text(content)}

      {:error, :not_found} ->
        {:ok, Snodo.Result.error("README not found for '#{name}'.")}

      {:error, reason} ->
        {:ok, Snodo.Result.error("Failed to get README: #{inspect(reason)}")}
    end
  end
end
