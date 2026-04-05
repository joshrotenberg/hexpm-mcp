defmodule HexpmMcp.MCP.Tools.Alternatives do
  @moduledoc """
  Find and compare alternative packages for a given hex.pm package.
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
    case HexpmMcp.find_alternatives(name) do
      {:ok, data} ->
        {:reply, Response.text(Response.tool(), Formatter.format_alternatives(data)), frame}

      {:error, :not_found} ->
        {:reply, Response.text(Response.tool(), "Package '#{name}' not found."), frame}

      {:error, reason} ->
        {:error, Error.execution("Failed to find alternatives: #{inspect(reason)}"), frame}
    end
  end
end
