defmodule HexpmMcp.MCP.Resources.PackageDocs do
  @moduledoc "Get documentation module listing for a hex.pm package"

  use Anubis.Server.Component,
    type: :resource,
    name: "package_docs",
    uri_template: "hex://{name}/docs",
    mime_type: "application/json"

  alias Anubis.MCP.Error
  alias Anubis.Server.Response
  alias HexpmMcp.HexDocs

  @impl true
  def read(%{"name" => pkg_name}, frame) do
    case HexDocs.get_modules(pkg_name) do
      {:ok, modules} ->
        {:reply, Response.json(Response.resource(), modules), frame}

      {:error, reason} ->
        {:error, Error.execution("Docs not found: #{inspect(reason)}"), frame}
    end
  end
end
