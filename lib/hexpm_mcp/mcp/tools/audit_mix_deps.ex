defmodule HexpmMcp.MCP.Tools.AuditMixDeps do
  @moduledoc """
  Audit mix.exs dependencies for risks.
  """

  use Anubis.Server.Component, type: :tool

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
    case HexpmMcp.audit_mix_deps(deps) do
      {:ok, audit} ->
        {:reply, Response.text(Response.tool(), Formatter.format_mix_audit(audit)), frame}

      {:error, :no_deps_found} ->
        {:reply, Response.text(Response.tool(), "No dependencies found in the provided text."),
         frame}
    end
  end
end
