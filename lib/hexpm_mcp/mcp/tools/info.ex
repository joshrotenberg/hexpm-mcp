defmodule HexpmMcp.MCP.Tools.Info do
  @moduledoc """
  Get detailed information about a hex.pm package.
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
    case HexpmMcp.get_info(name) do
      {:ok, info} ->
        {:reply, Response.text(Response.tool(), Formatter.format_package_info(info)), frame}

      {:error, :not_found} ->
        {:reply, Response.text(Response.tool(), "Package '#{name}' not found on hex.pm."), frame}

      {:error, reason} ->
        {:error, Error.execution("Failed to get package info: #{inspect(reason)}"), frame}
    end
  end
end
