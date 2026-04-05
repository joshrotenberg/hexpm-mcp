defmodule HexpmMcp.MCP.Tools.Dependencies do
  @moduledoc """
  Get dependencies for a package version.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.MCP.Error
  alias Anubis.Server.Response
  alias HexpmMcp.Formatter

  schema do
    field(:name, :string, required: true, description: "Package name on hex.pm")
    field(:version, :string, description: "Release version (defaults to latest)")
  end

  @impl true
  def execute(%{name: name} = args, frame) do
    version = Map.get(args, :version)

    case HexpmMcp.get_dependencies(name, version) do
      {:ok, data} ->
        {:reply, Response.text(Response.tool(), Formatter.format_dependencies(data)), frame}

      {:error, :not_found} ->
        {:reply, Response.text(Response.tool(), "Package '#{name}' not found."), frame}

      {:error, reason} ->
        {:error, Error.execution("Failed to get dependencies: #{inspect(reason)}"), frame}
    end
  end
end
