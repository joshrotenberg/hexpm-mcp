defmodule HexpmMcp.MCP.Tools.AuditMixDeps do
  @moduledoc """
  Audit mix.exs dependencies for risks.
  """

  use Snodo.Tool.Simple,
    name: "audit_mix_deps",
    description: "Audit mix.exs dependencies for risks"

  alias HexpmMcp.Formatter

  argument("deps", :string,
    required: true,
    description: "Mix.exs deps list as text, e.g. {:phoenix, \"~> 1.7\"}, {:ecto, \"~> 3.10\"}"
  )

  @impl true
  def call(%{"deps" => deps}, _context) do
    case HexpmMcp.audit_mix_deps(deps) do
      {:ok, audit} ->
        {:ok, Snodo.Result.text(Formatter.format_mix_audit(audit))}

      {:error, :no_deps_found} ->
        {:ok, Snodo.Result.error("No dependencies found in the provided text.")}
    end
  end
end
