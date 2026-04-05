defmodule HexpmMcp.MCP.Tools.Readme do
  @moduledoc """
  Get the README content for a hex.pm package.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.MCP.Error
  alias Anubis.Server.Response

  schema do
    field(:name, :string, required: true, description: "Package name on hex.pm")
    field(:version, :string, description: "Package version (defaults to latest)")
  end

  @impl true
  def execute(%{name: name} = args, frame) do
    version = Map.get(args, :version)

    case HexpmMcp.get_readme(name, version) do
      {:ok, content} ->
        {:reply, Response.text(Response.tool(), content), frame}

      {:error, :not_found} ->
        {:reply, Response.text(Response.tool(), "README not found for '#{name}'."), frame}

      {:error, reason} ->
        {:error, Error.execution("Failed to get README: #{inspect(reason)}"), frame}
    end
  end
end
