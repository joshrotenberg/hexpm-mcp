defmodule HexpmMcp.MCP.Resources.PackageInfo do
  @moduledoc "Get package metadata from hex.pm"

  use Anubis.Server.Component,
    type: :resource,
    name: "package_info",
    uri_template: "hex://{name}/info",
    mime_type: "application/json"

  alias Anubis.MCP.Error
  alias Anubis.Server.Response
  alias HexpmMcp.Client

  @impl true
  def read(%{"name" => pkg_name}, frame) do
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

        {:reply, Response.json(Response.resource(), data), frame}

      {:error, reason} ->
        {:error, Error.execution("Package not found: #{inspect(reason)}"), frame}
    end
  end
end
