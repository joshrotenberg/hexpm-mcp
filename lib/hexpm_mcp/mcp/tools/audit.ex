defmodule HexpmMcp.MCP.Tools.Audit do
  @moduledoc """
  Audit a package's dependencies for risks.

  Checks each dependency for retired versions, stale packages,
  single-owner packages, and known vulnerabilities via OSV.dev.
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

    case HexpmMcp.audit_dependencies(name, version) do
      {:ok, audit} ->
        {:reply, Response.text(Response.tool(), Formatter.format_audit(audit)), frame}

      {:error, :not_found} ->
        {:reply, Response.text(Response.tool(), "Package '#{name}' not found."), frame}

      {:error, reason} ->
        {:error, Error.execution("Audit failed: #{inspect(reason)}"), frame}
    end
  end
end
