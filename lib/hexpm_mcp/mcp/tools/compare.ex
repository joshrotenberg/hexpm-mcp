defmodule HexpmMcp.MCP.Tools.Compare do
  @moduledoc """
  Compare 2-5 hex.pm packages side by side.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias HexpmMcp.Formatter

  schema do
    field(:packages, :string,
      required: true,
      description: "Comma-separated list of package names (2-5 packages)"
    )
  end

  @impl true
  def execute(%{packages: packages_str}, frame) do
    names =
      packages_str
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    case HexpmMcp.compare_packages(names) do
      {:ok, packages} ->
        {:reply, Response.text(Response.tool(), Formatter.format_comparison(packages)), frame}

      {:error, :too_few_packages} ->
        {:reply, Response.text(Response.tool(), "Please provide at least 2 package names."),
         frame}

      {:error, :too_many_packages} ->
        {:reply, Response.text(Response.tool(), "Please provide at most 5 package names."), frame}
    end
  end
end
