defmodule HexpmMcp.MCP.Tools.DepTree do
  @moduledoc """
  Get the full transitive dependency tree for a package (BFS, max depth 5).
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.MCP.Error
  alias Anubis.Server.Response
  alias HexpmMcp.Formatter

  schema do
    field(:name, :string, required: true, description: "Package name on hex.pm")
    field(:version, :string, description: "Release version (defaults to latest)")
    field(:max_depth, :integer, description: "Maximum depth to traverse (default 5, max 5)")
  end

  @impl true
  def execute(%{name: name} = args, frame) do
    version = Map.get(args, :version)
    opts = if max_depth = Map.get(args, :max_depth), do: [max_depth: max_depth], else: []

    case HexpmMcp.dependency_tree(name, version, opts) do
      {:ok, data} ->
        {:reply, Response.text(Response.tool(), Formatter.format_dependency_tree(data)), frame}

      {:error, :not_found} ->
        {:reply, Response.text(Response.tool(), "Package '#{name}' not found."), frame}

      {:error, reason} ->
        {:error, Error.execution("Failed to build dependency tree: #{inspect(reason)}"), frame}
    end
  end
end
