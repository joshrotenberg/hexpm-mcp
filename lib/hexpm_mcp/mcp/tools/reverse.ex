defmodule HexpmMcp.MCP.Tools.Reverse do
  @moduledoc """
  Find packages that depend on a given hex.pm package.
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
    case HexpmMcp.get_reverse_dependencies(name) do
      {:ok, data} ->
        {:reply, Response.text(Response.tool(), Formatter.format_reverse_dependencies(data)),
         frame}

      {:error, :not_found} ->
        {:reply, Response.text(Response.tool(), "Package '#{name}' not found."), frame}

      {:error, reason} ->
        {:error, Error.execution("Failed to get reverse dependencies: #{inspect(reason)}"), frame}
    end
  end
end
