defmodule HexpmMcp.MCP.Tools.Release do
  @moduledoc """
  Get detailed information about a specific package release.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.MCP.Error
  alias Anubis.Server.Response
  alias HexpmMcp.Formatter

  schema do
    field(:name, :string, required: true, description: "Package name on hex.pm")
    field(:version, :string, required: true, description: "Release version (e.g. \"1.8.5\")")
  end

  @impl true
  def execute(%{name: name, version: version}, frame) do
    case HexpmMcp.get_release(name, version) do
      {:ok, data} ->
        {:reply, Response.text(Response.tool(), Formatter.format_release(data)), frame}

      {:error, :not_found} ->
        {:reply, Response.text(Response.tool(), "Release #{name} v#{version} not found."), frame}

      {:error, reason} ->
        {:error, Error.execution("Failed to get release: #{inspect(reason)}"), frame}
    end
  end
end
