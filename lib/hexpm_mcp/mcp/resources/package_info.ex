defmodule HexpmMcp.MCP.Resources.PackageInfo do
  @moduledoc "Get package metadata from hex.pm"

  use MCP.Resource,
    name: "package_info",
    description: "Get package metadata from hex.pm",
    uri_template: "hex://{name}/info",
    mime_type: "application/json",
    completion_arguments: ["name"]

  alias HexpmMcp.Client
  alias HexpmMcp.MCP.PackageCompletion

  @impl true
  def complete(%MCP.Completion{argument: "name", value: prefix}, _context) do
    PackageCompletion.complete(prefix)
  end

  @impl true
  def read(%{"uri" => uri, "name" => pkg_name}, _context) do
    case Client.get_package(pkg_name) do
      {:ok, pkg} ->
        data = %{
          name: pkg.name,
          latest_version: pkg.latest_version,
          latest_stable_version: pkg.latest_stable_version,
          description: get_in(pkg.meta, ["description"]),
          licenses: get_in(pkg.meta, ["licenses"]) || [],
          links: get_in(pkg.meta, ["links"]) || %{},
          downloads: pkg.downloads,
          inserted_at: pkg.inserted_at,
          updated_at: pkg.updated_at
        }

        {:ok, MCP.Result.resource_read(MCP.Resource.json(uri, MCP.JSONValue.encodable!(data)))}

      {:error, :not_found} ->
        {:error, MCP.Error.invalid_params("Resource not found", %{"uri" => uri})}

      {:error, reason} ->
        {:error, MCP.Error.execution("Package not found: #{inspect(reason)}")}
    end
  end
end
