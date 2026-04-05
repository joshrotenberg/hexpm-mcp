defmodule HexpmMcp.MCP.Resources.PackageReadme do
  @moduledoc "Get README content for a hex.pm package"

  use Anubis.Server.Component,
    type: :resource,
    name: "package_readme",
    uri_template: "hex://{name}/readme",
    mime_type: "text/markdown"

  alias Anubis.MCP.Error
  alias Anubis.Server.Response
  alias HexpmMcp.HexDocs

  @impl true
  def read(%{"name" => pkg_name}, frame) do
    case HexDocs.get_readme(pkg_name) do
      {:ok, content} ->
        {:reply, Response.text(Response.resource(), content), frame}

      {:error, reason} ->
        {:error, Error.execution("README not found: #{inspect(reason)}"), frame}
    end
  end
end
