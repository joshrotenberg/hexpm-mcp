defmodule HexpmMcp.MCP.Resources.PackageReadme do
  @moduledoc "Get README content for a hex.pm package"

  use MCP.Resource.Simple,
    name: "package_readme",
    description: "Get README content for a hex.pm package",
    uri_template: "hex://{name}/readme",
    mime_type: "text/markdown"

  alias HexpmMcp.HexDocs

  @impl true
  def read(%{"uri" => uri, "name" => pkg_name}, _context) do
    case HexDocs.get_readme(pkg_name) do
      {:ok, content} ->
        {:ok, content}

      {:error, :not_found} ->
        {:error, MCP.Error.invalid_params("Resource not found", %{"uri" => uri})}

      {:error, reason} ->
        {:error, MCP.Error.execution("README not found: #{inspect(reason)}")}
    end
  end
end
