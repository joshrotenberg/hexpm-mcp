defmodule HexpmMcp.MCP.Tools.UpgradeCheck do
  @moduledoc """
  Check which mix.exs dependencies have newer versions available.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.MCP.Error
  alias Anubis.Server.Response
  alias HexpmMcp.Formatter

  schema do
    field(:deps, :string,
      required: true,
      description: "Mix.exs deps list as text, e.g. {:phoenix, \"~> 1.7\"}, {:ecto, \"~> 3.10\"}"
    )
  end

  @impl true
  def execute(%{deps: deps}, frame) do
    case HexpmMcp.upgrade_check(deps) do
      {:ok, data} ->
        {:reply, Response.text(Response.tool(), Formatter.format_upgrade_check(data)), frame}

      {:error, :no_deps_found} ->
        {:reply, Response.text(Response.tool(), "No dependencies found in the provided text."),
         frame}

      {:error, reason} ->
        {:error, Error.execution("Upgrade check failed: #{inspect(reason)}"), frame}
    end
  end
end
