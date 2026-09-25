defmodule HexpmMcp.MCP.Tools.Compare do
  @moduledoc """
  Compare 2-5 hex.pm packages side by side.
  """

  use Snodo.Tool.Simple, name: "compare", description: "Compare 2-5 packages side by side"

  alias HexpmMcp.Formatter

  argument("packages", :string,
    required: true,
    description: "Comma-separated list of package names (2-5 packages)"
  )

  @impl true
  def call(%{"packages" => packages_str}, _context) do
    names =
      packages_str
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    case HexpmMcp.compare_packages(names) do
      {:ok, packages} ->
        {:ok, Snodo.Result.text(Formatter.format_comparison(packages))}

      {:error, :too_few_packages} ->
        {:ok, Snodo.Result.error("Please provide at least 2 package names.")}

      {:error, :too_many_packages} ->
        {:ok, Snodo.Result.error("Please provide at most 5 package names.")}
    end
  end
end
