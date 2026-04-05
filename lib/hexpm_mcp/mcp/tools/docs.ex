defmodule HexpmMcp.MCP.Tools.Docs do
  @moduledoc """
  Browse package documentation -- module listing.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.MCP.Error
  alias Anubis.Server.Response
  alias HexpmMcp.Formatter

  schema do
    field(:name, :string, required: true, description: "Package name on hex.pm")
    field(:version, :string, description: "Package version (defaults to latest)")
  end

  @impl true
  def execute(%{name: name} = args, frame) do
    version = Map.get(args, :version)

    case HexpmMcp.get_docs(name, version) do
      {:ok, modules} when modules != [] ->
        {:reply, Response.text(Response.tool(), Formatter.format_docs(name, version, modules)),
         frame}

      {:ok, []} ->
        {:reply, Response.text(Response.tool(), "No modules found for '#{name}'."), frame}

      {:error, :not_found} ->
        {:reply, Response.text(Response.tool(), "Documentation not found for '#{name}'."), frame}

      {:error, reason} ->
        {:error, Error.execution("Failed to get docs: #{inspect(reason)}"), frame}
    end
  end
end
