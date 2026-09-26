defmodule HexpmMcp.MCP.Resources.PackageDocs do
  @moduledoc "Get documentation module listing for a hex.pm package"

  use Snodo.Resource.Simple,
    name: "package_docs",
    description: "Get documentation module listing for a hex.pm package",
    uri_template: "hex://{name}/docs",
    mime_type: "application/json"

  alias HexpmMcp.HexDocs

  @impl true
  def read(%{"uri" => uri, "name" => pkg_name}, _context) do
    case HexDocs.get_modules(pkg_name) do
      {:ok, modules} ->
        {:ok, Snodo.JSONValue.encodable!(modules)}

      {:error, :not_found} ->
        {:error, Snodo.Error.invalid_params("Resource not found", %{"uri" => uri})}

      {:error, reason} ->
        {:error, Snodo.Error.execution("Docs not found: #{inspect(reason)}")}
    end
  end
end
