defmodule HexpmMcp.MCP.Tools.Features do
  @moduledoc """
  Get optional features/extras for a package release.
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

    case HexpmMcp.get_features(name, version) do
      {:ok, data} ->
        {:reply, Response.text(Response.tool(), Formatter.format_features(data)), frame}

      {:error, :not_found} ->
        {:reply, Response.text(Response.tool(), "Package '#{name}' not found."), frame}

      {:error, reason} ->
        {:error, Error.execution("Failed to get features: #{inspect(reason)}"), frame}
    end
  end
end
