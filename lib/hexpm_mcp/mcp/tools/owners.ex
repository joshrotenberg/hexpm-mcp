defmodule HexpmMcp.MCP.Tools.Owners do
  @moduledoc """
  Get owners/maintainers of a hex.pm package.
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
    case HexpmMcp.get_owners(name) do
      {:ok, owners} ->
        {:reply, Response.text(Response.tool(), Formatter.format_owners(name, owners)), frame}

      {:error, :not_found} ->
        {:reply, Response.text(Response.tool(), "Package '#{name}' not found."), frame}

      {:error, reason} ->
        {:error, Error.execution("Failed to get owners: #{inspect(reason)}"), frame}
    end
  end
end
