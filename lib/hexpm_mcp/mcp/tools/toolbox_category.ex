defmodule HexpmMcp.MCP.Tools.ToolboxCategory do
  @moduledoc """
  List the curated projects in an Elixir Toolbox category.
  """

  use Snodo.Tool.Simple,
    name: "toolbox_category",
    description: "List projects in a Toolbox category"

  alias HexpmMcp.Formatter

  argument("group", :string, required: true, description: "Group slug (e.g. \"web\", \"ai\")")

  argument("category", :string,
    required: true,
    description: "Category slug within the group (e.g. \"frameworks\")"
  )

  argument("sort", :string,
    description:
      "Ordering: \"name\" (alphabetical) or \"downloads\"; defaults to popularity order"
  )

  @impl true
  def call(%{"group" => group, "category" => category} = args, _context) do
    opts = maybe_put([], :sort, Map.get(args, "sort"))

    case HexpmMcp.toolbox_category(group, category, opts) do
      {:ok, projects} ->
        {:ok, Snodo.Result.text(Formatter.format_toolbox_category(group, category, projects))}

      {:error, :not_found} ->
        {:ok, Snodo.Result.error("Category not found: #{group}/#{category}")}

      {:error, reason} ->
        {:ok, Snodo.Result.error("Failed to fetch category projects: #{inspect(reason)}")}
    end
  end

  defp maybe_put(keyword, _key, nil), do: keyword
  defp maybe_put(keyword, key, value), do: Keyword.put(keyword, key, value)
end
