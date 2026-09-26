defmodule HexpmMcp.MCP.Tools.UpgradeCheck do
  @moduledoc """
  Check which mix.exs dependencies have newer versions available.
  """

  use Snodo.Tool.Simple,
    name: "upgrade_check",
    description: "Check mix.exs dependencies for upgrades"

  alias HexpmMcp.Formatter

  argument("deps", :string,
    required: true,
    description: "Mix.exs deps list as text, e.g. {:phoenix, \"~> 1.7\"}, {:ecto, \"~> 3.10\"}"
  )

  @impl true
  def call(%{"deps" => deps}, _context) do
    case HexpmMcp.upgrade_check(deps) do
      {:ok, data} ->
        {:ok, Snodo.Result.text(Formatter.format_upgrade_check(data))}

      {:error, :no_deps_found} ->
        {:ok, Snodo.Result.error("No dependencies found in the provided text.")}
    end
  end
end
