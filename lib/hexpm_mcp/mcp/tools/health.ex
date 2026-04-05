defmodule HexpmMcp.MCP.Tools.Health do
  @moduledoc """
  Comprehensive health check for a hex.pm package.
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
    case HexpmMcp.health_check(name) do
      {:ok, health} ->
        {:reply, Response.text(Response.tool(), Formatter.format_health_check(health)), frame}

      {:error, :not_found} ->
        {:reply, Response.text(Response.tool(), "Package '#{name}' not found."), frame}

      {:error, reason} ->
        {:error, Error.execution("Health check failed: #{inspect(reason)}"), frame}
    end
  end
end
