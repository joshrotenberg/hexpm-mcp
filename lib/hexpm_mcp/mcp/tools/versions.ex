defmodule HexpmMcp.MCP.Tools.Versions do
  @moduledoc """
  List all versions of a hex.pm package.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.MCP.Error
  alias Anubis.Server.Response
  alias HexpmMcp.Formatter

  schema do
    field(:name, :string, required: true, description: "Package name on hex.pm")
  end

  @impl true
  def execute(%{name: name}, frame) do
    case HexpmMcp.get_versions(name) do
      {:ok, data} ->
        {:reply, Response.text(Response.tool(), Formatter.format_versions(data)), frame}

      {:error, :not_found} ->
        {:reply, Response.text(Response.tool(), "Package '#{name}' not found on hex.pm."), frame}

      {:error, reason} ->
        {:error, Error.execution("Failed to get versions: #{inspect(reason)}"), frame}
    end
  end
end
