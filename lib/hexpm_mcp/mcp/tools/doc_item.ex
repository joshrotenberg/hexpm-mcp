defmodule HexpmMcp.MCP.Tools.DocItem do
  @moduledoc """
  Get full documentation for a specific module or function.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.MCP.Error
  alias Anubis.Server.Response

  schema do
    field(:name, :string, required: true, description: "Package name on hex.pm")
    field(:module, :string, required: true, description: "Module name (e.g. \"Plug.Conn\")")
    field(:version, :string, description: "Package version (defaults to latest)")
  end

  @impl true
  def execute(%{name: name, module: module} = args, frame) do
    version = Map.get(args, :version)

    case HexpmMcp.get_doc_item(name, module, version) do
      {:ok, content} ->
        {:reply, Response.text(Response.tool(), content), frame}

      {:error, :not_found} ->
        {:reply,
         Response.text(Response.tool(), "Documentation for #{module} not found in '#{name}'."),
         frame}

      {:error, reason} ->
        {:error, Error.execution("Failed to get doc item: #{inspect(reason)}"), frame}
    end
  end
end
