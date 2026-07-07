defmodule HexpmMcp.MCP.Tools.ToolboxCategory do
  @moduledoc """
  List the curated projects in an Elixir Toolbox category.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.MCP.Error
  alias Anubis.Server.Response
  alias HexpmMcp.Formatter

  schema do
    field(:group, :string, required: true, description: "Group slug (e.g. \"web\", \"ai\")")

    field(:category, :string,
      required: true,
      description: "Category slug within the group (e.g. \"frameworks\")"
    )

    field(:sort, :string,
      description:
        "Ordering: \"name\" (alphabetical) or \"downloads\"; defaults to popularity order"
    )
  end

  @impl true
  def execute(%{group: group, category: category} = args, frame) do
    opts = maybe_put([], :sort, Map.get(args, :sort))

    case HexpmMcp.toolbox_category(group, category, opts) do
      {:ok, projects} ->
        {:reply,
         Response.text(
           Response.tool(),
           Formatter.format_toolbox_category(group, category, projects)
         ), frame}

      {:error, :not_found} ->
        {:error, Error.execution("Category not found: #{group}/#{category}"), frame}

      {:error, reason} ->
        {:error, Error.execution("Failed to fetch category projects: #{inspect(reason)}"), frame}
    end
  end

  defp maybe_put(keyword, _key, nil), do: keyword
  defp maybe_put(keyword, key, value), do: Keyword.put(keyword, key, value)
end
